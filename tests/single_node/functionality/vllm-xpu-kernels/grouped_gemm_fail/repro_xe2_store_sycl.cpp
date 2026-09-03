// repro_xe2_store_sycl.cpp
//
// SYCL standalone reproducer for the XE2 D-store path.
//
// The native XE2 D-store path must fill every element of C with one.

#include <sycl/sycl.hpp>

#include <cute/tensor.hpp>
#include <cute/util/compat.hpp>

#include <iostream>
#include <limits>

#include "vllm-xpu-kernels/csrc/xpu/grouped_gemm/xe_2/gemm_xe2.hpp"

namespace {
using namespace cute;
namespace syclex = sycl::ext::oneapi::experimental;
namespace intelex = sycl::ext::intel::experimental;

// Row-major global-memory tensor helper.
template <typename T>
CUTE_HOST_DEVICE auto make_row_major_tensor(T* ptr, int rows, int cols) {
  return make_tensor(
      make_gmem_ptr(ptr),
      make_layout(make_shape(rows, cols), make_stride(cols, _1{})));
}

// FP16 XE2 grouped-GEMM output tile.
using GroupedGemmTiledMMA = cute::TiledMMA<
    cute::MMA_Atom<cute::XE_DPAS_TT<8, float, cutlass::half_t>>,
    cute::Layout<
        cute::tuple<cute::C<1>, cute::C<4>, cute::C<1>>,
        cute::tuple<cute::C<4>, cute::C<1>, cute::C<0>>>,
    const cute::tuple<
        cute::Layout<cute::C<16>>,
        cute::Layout<cute::C<64>, cute::C<1>>,
        cute::Layout<cute::C<32>>>>;

void run_once(sycl::queue& q, cutlass::half_t* d_ptr, int M, int N) {
  constexpr int local_threads = 512;

  syclex::properties kernel_props{
      syclex::sub_group_size<16>,
      intelex::grf_size<256>,
  };

  q.submit([&](sycl::handler& cgh) {
     cgh.parallel_for(
         sycl::nd_range<3>{sycl::range<3>{1, local_threads, 1},
                           sycl::range<3>{1, local_threads, 1}},
         kernel_props,
         [=](sycl::nd_item<3> item) {
           int local_id = item.get_local_linear_id();

           GroupedGemmTiledMMA mma{};

           // Real output tensor C(M,N), row-major.
           auto C = make_row_major_tensor(d_ptr, M, N);

           // Same coordinate-tensor flow as xe_gemm.
           Tensor cC = make_identity_tensor(C.shape());
           auto wg_tile = mma.tile_mnk();
           auto wg_coord = make_coord(0, 0, 0);
           Tensor gC =
               local_tile(cC, wg_tile, wg_coord, Step<_1, _1, X>{});

           auto copy_c = get_block_2d_copy_D<void>(mma, C);

           auto thr_mma = mma.get_slice(local_id);
           auto thr_copy_c = copy_c.get_slice(local_id);
           SubgroupTensor tCrC = thr_mma.partition_sg_fragment_C(gC);
           Tensor tCgC = thr_copy_c.partition_D(gC);
           SubgroupTensor tCrC_out =
               thr_copy_c.partition_sg_fragment_S(gC);

           using TD = typename decltype(C)::element_type;

           // Build the same MMA and output fragments as the real epilogue.
           TD frag[tCrC.size()];
           TD frag_out[tCrC_out.size()];
           Tensor frag_tensor =
               make_tensor(make_rmem_ptr(frag), tCrC.layout());
           Tensor frag_out_tensor =
               make_tensor(make_rmem_ptr(frag_out), tCrC_out.layout());
           SubgroupTensor frag_sg =
               make_subgroup_tensor(frag_tensor, tCrC.tv_layout());
           SubgroupTensor frag_out_sg =
               make_subgroup_tensor(frag_out_tensor, tCrC_out.tv_layout());

           CUTE_UNROLL
           for (int i = 0; i < tCrC.size(); ++i) {
             frag[i] = TD(1.0f);
           }
           reorder(frag_sg, frag_out_sg);

           copy(copy_c, frag_out_sg, tCgC);
         });
   }).wait_and_throw();
}

void fill_nan(cutlass::half_t* ptr, size_t n) {
  cutlass::half_t nanv = cutlass::half_t(std::numeric_limits<float>::quiet_NaN());
  for (size_t i = 0; i < n; ++i) {
    ptr[i] = nanv;
  }
}

long count_nans(const cutlass::half_t* ptr, size_t n) {
  long out = 0;
  for (size_t i = 0; i < n; ++i) {
    if (std::isnan(static_cast<float>(ptr[i]))) {
      ++out;
    }
  }
  return out;
}

void print_col0(const char* label, const cutlass::half_t* ptr, int M, int N) {
  std::cout << label << " D[:,0] = [";
  for (int m = 0; m < M; ++m) {
    if (m) std::cout << ", ";
    float v = static_cast<float>(ptr[m * N + 0]);
    if (std::isnan(v)) std::cout << "nan";
    else std::cout << v;
  }
  std::cout << "]\n";
}

void print_row0(const char* label, const cutlass::half_t* ptr, int N) {
  std::cout << label << " D[0,0:8] = [";
  for (int i = 0; i < 8; ++i) {
    if (i) std::cout << ", ";
    float v = static_cast<float>(ptr[i]);
    if (std::isnan(v)) std::cout << "nan";
    else std::cout << v;
  }
  std::cout << "]\n";
}

}  // namespace

int main() {
  constexpr int M = 4;
  constexpr int N = 512;
  constexpr size_t elems = size_t(M) * size_t(N);

  sycl::queue q{sycl::gpu_selector_v};

  auto* output = sycl::malloc_shared<cutlass::half_t>(elems, q);

  if (!output) {
    std::cerr << "malloc_shared failed\n";
    return 1;
  }

  fill_nan(output, elems);

  run_once(q, output, M, N);

  auto num_nans = count_nans(output, elems);
  bool all_ones = true;
  for (size_t i = 0; i < elems; ++i) {
    all_ones &= static_cast<float>(output[i]) == 1.0f;
  }

  std::cout << "nan count: " << num_nans << "\n";
  print_col0("output", output, M, N);
  print_row0("output", output, N);

  sycl::free(output, q);
  if (num_nans != 0 || !all_ones) {
    return 1;
  } else {
    return 0;
  }
}
