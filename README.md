# Sensu plugin for monitoring disk usage

A sensu plugin to monitor disk usage on Linux.

The plugin generates multiple OK/WARN/CRIT/UNKNOWN events via the sensu client socket (https://sensuapp.org/docs/latest/clients#client-socket-input)
so that you do not miss state changes when monitoring multiple volumes.

## Usage

The plugin accepts the following command line options:

```
Usage: check-disk-usage.rb (options)
    -c, --config <PATH>              Optional configuration file (default: ./disk-usage.json)
        --crit-inodes <PERCENT>      Critical if PERCENT or more of inodes used
        --crit-space <PERCENT>       Critical if PERCENT or more of disk space used
        --fstype <TYPE>              Comma separated list of file system type(s) (default: all)
        --ignore-fstype <TYPE>       Comma separated list of file system type(s) to ignore
        --ignore-mount <MOUNTPOINT>  Comma separated list of mount point(s) to ignore
        --ignore-mount-regex <MOUNTPOINT>
                                     Comma separated list of mount point(s) to ignore (regex)
        --mount <MOUNTPOINT>         Comma separated list of mount point(s) (default: all)
        --mount-regex <MOUNTPOINT>   Comma separated list of mount point(s) (regex)
    -w, --warn                       Warn instead of throwing a critical failure
        --warn-inodes <PERCENT>      Warn if PERCENT or more of inodes used
        --warn-space <PERCENT>       Warn if PERCENT or more of disk space used
```

By default, the warning and critical parameters are global to all mountpoints. However, each mountpoint can override the defaults in an optional JSON configuration file which must be placed
in the same location as the plugin.

JSON example:

```
{
  "mountpoints": {
    "/": {
      "warn_space": 70,
      "crit_space": 85,
      "warn_inodes": 65,
      "crit_inodes": 75
    },
    ..
  }
}
```

## Author
Matteo Cerutti - <matteo.cerutti@hotmail.co.uk>
