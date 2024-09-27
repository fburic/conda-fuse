# Conda environments as a FUSE

Scripts to help manage [conda](https://docs.conda.io) environments
stored as compressed archives and exposed as FUSE mounts to conda.

This allows creating a single zip file out of a conda environment directory,
dramatically reducing the number of files stored on the native file system,
as well as potentially also reducing the total size.
This zip file is mounted as a directory and is then accessible to conda
(or any other operation) normally.
When unmounted, the zip is updated with any changes made to this directory.

This is known as a
[filesystem in user space](https://en.wikipedia.org/wiki/Filesystem_in_Userspace),
an interface that allows the contents of various file formats like archives
to be viewed and manipulated as normal files.
It also does not require administrative privileges (the "user" space part).


## Requirements

- Linux system. This should be easy to adapt to macOS, however.
- `fuse-zip`, `fuse3`, `libfuse3-dev` (on Debian / Ubuntu) or `fuse-devel` (on Red Hat / CentOS)
- `conda >= 4.4`

The current implementation relies on `fuse-zip`, due to its availability,
though it is limited to single-threaded operations.


## Setup

The bash library `conda-fuse.sh` defines functions for working with conda environments
with FUSE-mounted archives: 
`conda-fuse-create`, `conda-fuse-activate`, `conda-fuse-unmount`,
`conda-fuse-paths`, `conda-fuse-env-list`

This file is meant to be sourced in order to define variables and functions
in the current working context (scripts or login session).
For common interactive use, this could for instance be done in `.bashrc`
(i.e. as `source conda-fuse.sh`).

The path variables in `conda-fuse.sh` define where archives are created and mounted,
respectively, by default in the home directory. You may wish to change these.

- `CONDA_FUSE_MOUNT_ROOT`: Directory in which the env archives are mounted.
  Default `$HOME/miniconda_fuse/envs`
- `CONDA_FUSE_ARCHIVE_PATH`: Where to store the `.zip` archives of conda envs.
  Default: `$HOME/miniconda_fuse/archives`
- `TMPDIR`: Which directory to be used for temporary storage. 
  Only used for the initial creation of empty zip files. 
  Default is `/tmp` but some systems may have it somewhere else or the user may
  wish to use another location.


## Usage

:warning: **Important** 
Please be careful to unmount the environment if powering off the computer or logging out,
and generally when done working with that environment. 
Any changes to the env directory contents are only written back to the archive
during unmounting.
So to avoid losing changes, make sure to properly close down the conda-fuse env (see below).
For the same reason, unmounting may take a little while to complete 
(should be at most a few minutes, typically), when working with larger environments.
This is a limitation of working with zip.


### Creating an environment

To create a new conda environment, run:

```bash
conda-fuse-create [env name] [args to pass to conda]
```

and answer with `y` when prompted with the warning from conda that the target
directory exists (this directory is empty, created to house the env files),
and again with `y` when confirming the creation process (as per usual).

If an environment archive already exists with that name, 
the function will mention this and terminate.
Run `conda-fuse-env-list` to see a list of existing conda-fuse envs, 
and the section below on deleting archives.

The function performs the following actions:
- creates a zip archive in `CONDA_FUSE_ARCHIVE_PATH` to hold the conda env files
- mounts that archive as `CONDA_FUSE_MOUNT_ROOT/env_name`
- calls `conda create` with a `--prefix` flag, explicitly telling conda
  [where to store the new environment](https://docs.conda.io/projects/conda/en/latest/user-guide/tasks/manage-environments.html#specifying-a-location-for-an-environment)

Note that the conda files will be stored in `CONDA_FUSE_MOUNT_ROOT/env_name/env_name`
This is because the first instance of `env_name` is the mount point, 
while the second is the directory named `env_name` *inside* the archive file.
While a bit awkward, this makes working with the archive more convenient,
including cases where the user may wish to manually extract it,
avoiding accidentally spilling its contents inside the working directory.

All other `[args to pass to conda]` are passed as-is to the `conda create` command.
These are typically the python version and optionally packages to be installed upon creation.
E.g. 

```bash
conda-fuse-create test-env python=3.11 numpy
```

resolves to 

```bash
conda create --prefix=${CONDA_FUSE_MOUNT_ROOT}/test-env python=3.11 numpy
```

The `env name` chosen for the environment works like a unique identifier, 
in much the same way it normally does for conda. 
It gives the name of the zip archive, 
as well as later indicating which archive to unmount.

For the example command above, the conda-fuse directories will look like this:

```shell
~/miniconda_fuse $ tree -L 4
.
├── archives
│   └── test-env.zip
└── envs
    └── test-env
        └── test-env
            ├── bin
            ├── compiler_compat
            ├── conda-meta
            ├── include
            ├── lib
            ├── licensing
            ├── man
            ├── share
            ├── ssl
            ├── x86_64-conda_cos7-linux-gnu
            └── x86_64-conda-linux-gnu
```

#### :point_right: Tip: Save env changes

When creating a large environment, or when installing many packages,
before you start working with the env,
it may be best to first save these changes by unmount it (see section below).
This way it's a bit safer, and you won't have to wait for changes to be written back 
at the end of your work session (maybe you'll be in a hurry then, 
and a large env will take a while to compress).


### Activating an environment

Conda can activate an environment at a given location by supplying it 
as an argument to the `conda activate` command.

A wrapper function is provided that will mount the environment archive if needed,
then activate the conda env,
by just passing the path of `env name` under `CONDA_FUSE_MOUNT_ROOT` to conda:

```bash
conda-fuse-activate [env name]
```

In the active environment, the user works with conda as usual 
(there's no conda-fuse layer or anything like that). 
Since this uses the prefix option for `conda activate`, the env prompt will show the full path.

For the example above, this will look similar the output below, 
where we also test the installed packages.

```
~ $ conda-fuse-activate test-env
(/home/user/miniconda_fuse/envs/test-env/test-env) user@hostname ~ $ python
 Python 3.11.9 (main, Apr 19 2024, 16:48:06) [GCC 11.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import numpy as np
>>> np.__version__
'2.0.1'
>>>
```

### Unmounting an environment

To avoid any weird behavior, first run `conda deactivate` if the environment in question
is currently active.

Then run:

```bash
conda-fuse-unmount [env name]
```

The `env name` uniquely identifies a conda-fuse environment.
Run `conda-fuse-env-list` to see the list of all conda-fuse envs
(more details in the next section).

You'll see the following in the terminal:

```
[conda-fuse] Waiting for fuse-zip processes to finish. Please be patient."
(waiting for zipping) ...  
```

This will take a little while (the dots will keep accumulating). 
If watching in e.g. `htop`, the CPU usage of the `fuse-zip` process will be evident.
This processes must be left alone to finish, in order to properly write back
any changes to the archive contents, which only occurs during unmounting.
Interrupting this process may lead to lost data and/or archive corruption.
While this is going on, `fuse-zip` writes to a temporary zip file in the same directory 
as the actual zip. When completely written, this temp file will replace the original.
So, for example:

```
~/miniconda_fuse $ ll archives/
total 139336
drwxrwxr-x 2 user user      4096 sep 24 17:39 .
drwxrwxr-x 4 user user      4096 sep 24 12:27 ..
-rw-rw-r-- 1 user user       168 sep 24 17:10 test-env.zip
-rw-rw-r-- 1 user user 142663680 sep 24 17:39 test-env.zip.vmel9u
```

The `conda-fuse-unmount` function polls `ps aux` until the `fuse-zip` command that
mounted the archive is no longer present. Only then will it finish.
This approach is taken since finding the PID of the FUSE process is problematic:
[[1]](https://sourceforge.net/p/fuse/mailman/fuse-devel/thread/47D9426B.5000000%40slax.org/)
[[2]](https://unix.stackexchange.com/questions/191821/find-what-process-implements-a-fuse-filesystem)

As a last step, the emtpy `CONDA_FUSE_MOUNT_ROOT/env_name` mount point is removed,
to keep this space tidy and avoid confusions about what is currently mounted.


### Listing existing conda-fuse environments

To get a list of all archived environments, as well as which ones are currently mounted,
run the `conda-fuse-env-list` function.

For the same example as before this will look something like this:

```shell
$ conda-fuse-env-list
Conda environment archives (in /home/user/miniconda_fuse/archives):
total 4,0K
-rw-rw-r-- 1 user user 168 sep 24 17:10 test-env.zip

Currently mounted environments (in /home/user/miniconda_fuse/envs):

1,1G    /home/user/miniconda_fuse/envs/test-env
1,1G    total
```

Note that the size of the zip file in the output above reflects the state
before any change to the contents in the mounted directory.
For this reason, as well as to keep track of potentially large decompressed environments,
the list of currently mounted envs uses `du` to show directory space usage
(including a total as the last item), so there may be a slight delay before full output.


### Deleting an environment

This is as simple as deleting the zip archive of that environment.
To promote user awareness of archive status
(location, which archives exist, how large they are, etc.),
there is no wrapper function for this.
Instead, the user is encouraged to run `conda-fuse-paths` to see the current
`CONDA_FUSE_ARCHIVE_PATH`, visit that location, and delete the archives they wish.
