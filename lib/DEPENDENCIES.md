# Vendored dependencies

All sources are ordinary repository files; neither dependency is a submodule.

| Dependency | Pinned release | Source archive | Delivered subset |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.0.2 | https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2 | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors, MIT license |
| forge-std | v1.9.6 | https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.6 | Complete `src/` and MIT/Apache licenses |

The OpenZeppelin subset is the complete import closure of this token. forge-std
is used only by tests. Source files are unmodified upstream copies. `remappings.txt`
resolves imports locally and the formatter excludes vendored source files.
