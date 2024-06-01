{
  nix-gitignore,
  lib,
  stdenv,
  zig,
}:
stdenv.mkDerivation {
  name = "modupdate-zig";

  src = nix-gitignore.gitignoreSource [] ./.;

  nativeBuildInputs = [
    zig.hook
  ];

  meta = with lib; {
    description = "Go modupdate in zig";
    homepage = "https://github.com/knightpp/modupdate-zig.git";
    license = licenses.mit;
    maintainers = with maintainers; [knightpp];
    mainProgram = "modupdate-zig";
    inherit (zig.meta) platforms;
  };
}
