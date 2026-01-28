with import <nixpkgs> { };

mkShell {
  packages = [
    shellcheck
    shfmt
  ];
}
