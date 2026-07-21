# No custom binaries in this directory.

The `pi-agent()` shell function (installed by `setup/install.sh` into your shell rc)
replaces the old `pi-gemma` / `pi-starbuck` binaries.

Launch via:
```bash
pi-agent                                    # default model (settings.json)
pi-agent --provider <name> --model <id>    # explicit
pi-gemma / pi-qwen                          # convenience aliases
```