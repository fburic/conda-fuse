if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] Don't run $0, source it. Run:  source $0" >&2
    exit 1
fi

export CONDA_FUSE_MOUNT_ROOT="$HOME/miniconda_fuse/envs"
export CONDA_FUSE_ARCHIVE_PATH="$HOME/miniconda_fuse/archives"
export TMPDIR='/tmp'


function conda-fuse-create {
    if [[ -n "$1" ]]; then
        local env_name=$1
        shift  # all other arguments are passed to conda
        mkdir -p "$CONDA_FUSE_MOUNT_ROOT"
        mkdir -p "$CONDA_FUSE_ARCHIVE_PATH"

        if [ -f "${CONDA_FUSE_ARCHIVE_PATH}/${env_name}.zip" ]; then
            echo "Environment archive already exists: ${CONDA_FUSE_ARCHIVE_PATH}/${env_name}"
            return 1
        fi

        # Create archive with empty directory.
        # Assume dirs under ${TMPDIR}/conda-fuse always empty and under conda-fuse control.
        # So repeated calls to create same env should just reuse same dir.
        echo "[conda-fuse] Creating env archive ${env_name}.zip"
        mkdir -p "${TMPDIR}/conda-fuse/${env_name}"
        (cd ${TMPDIR}/conda-fuse && zip -r "${env_name}.zip" "${env_name}")
        mv "${TMPDIR}/conda-fuse/${env_name}.zip" "${CONDA_FUSE_ARCHIVE_PATH}/"

        # Mount archive as background process
        local mount_point="${CONDA_FUSE_MOUNT_ROOT}/${env_name}"
        mkdir -p "$mount_point"
        fuse-zip "${CONDA_FUSE_ARCHIVE_PATH}/${env_name}.zip" "$mount_point"
        echo "[conda-fuse] Mounted env archive as $mount_point"

        # Create conda env
        # The double env_name is not a mistake. The first one is the mount point,
        # the second is the directory inside the archive.
        echo "[conda-fuse] Starting conda creation process..."
        conda create --prefix="${mount_point}/${env_name}" "$@"

    else
        echo "Create new conda environment as an archive and expose as a FUSE."
        echo "The compressed archive will be placed in CONDA_FUSE_ARCHIVE_PATH"
        echo "and that archive will then be mounted under CONDA_FUSE_MOUNT_ROOT"
        printf "\n Syntax:\n"
        printf "\t conda-fuse-create [env name] [args to pass to conda] \n\n"
    fi
}


function conda-fuse-activate {
    if [[ -n "$1" ]]; then
        local env_name=$1
        local mount_point="${CONDA_FUSE_MOUNT_ROOT}/${env_name}"

        # Mount if not already mounted
        if ! mountpoint -q "$mount_point"
        then
            mkdir -p "$mount_point"
            fuse-zip "${CONDA_FUSE_ARCHIVE_PATH}/${env_name}.zip" "$mount_point"
        fi

        # The double env_name is not a mistake. The first one is the mount point,
        # the second is the directory inside the archive.
        conda activate "${mount_point}/${env_name}"

    else
        echo "Mount conda-fuse environment archive and activate the conda env it contains"
        echo "from its mount path under CONDA_FUSE_MOUNT_ROOT"
        printf "\n Syntax: \n"
        printf "\t conda-fuse-activate [env name] \n\n"
    fi
}


function conda-fuse-unmount {
    if [[ -n "$1" ]]; then
        local env_name=$1
        local mount_point="${CONDA_FUSE_MOUNT_ROOT}/${env_name}"
        echo "[conda-fuse] Unmounting environment archive"
        fusermount -u "$mount_point"
        rmdir "$mount_point"

        echo "[conda-fuse] Waiting for fuse-zip processes to finish. Please be patient."
        local cmd_str="fuse-zip ${CONDA_FUSE_ARCHIVE_PATH}/${env_name}.zip ${mount_point}"
        while pgrep -f "$cmd_str" > /dev/null
        do
            sleep 10
            printf "."
        done
        printf "\n[conda-fuse] DONE\n\n"

    else
        echo "Deactivate conda environment and unmount its FUSE."
        printf "\nWARNING:\n"
        echo "This is the moment when any changes made to the environment"
        echo "are written back to the archive file."
        echo "Hence this process should be allowed to complete properly"
        echo "to avoid corrupting the archive."
        echo "If it doesn't immediately finish, it's very likely not hanged,"
        echo "just working. (Currently, single-threaded zip is used.)"
        printf "\n Syntax: \n"
        printf "\t conda-fuse-unmount [env name] \n\n"
    fi
}


function conda-fuse-paths {
    echo "Compressed archives: $CONDA_FUSE_ARCHIVE_PATH"
    echo "Mount point: $CONDA_FUSE_MOUNT_ROOT"
}


function conda-fuse-env-list {
    echo "Conda environment archives (in ${CONDA_FUSE_ARCHIVE_PATH}):"
    ls -lh "$CONDA_FUSE_ARCHIVE_PATH"

    printf "\nCurrently mounted environments (in %s):\n\n" "${CONDA_FUSE_MOUNT_ROOT}"
    find "$CONDA_FUSE_MOUNT_ROOT" -mindepth 1 -maxdepth 1 -exec du -h -d 0 {} \;

    # Total shown only if dir is not empty
    if [ "$(ls ${CONDA_FUSE_MOUNT_ROOT} | wc -l)" -gt 0 ]
    then
        du -d 0 -hc "$CONDA_FUSE_MOUNT_ROOT" | tail -n 1
    fi
    echo
}
