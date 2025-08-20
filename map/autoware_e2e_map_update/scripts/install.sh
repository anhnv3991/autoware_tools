#!/bin/bash

set -eo pipefail
shopt -s nullglob

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_the_installation_folder>"
    exit 1
fi 

# Install all necessary tools for PCD map update
CURRENT_DIR="$(pwd)"
MAP4_PATH=$1

# Install MapIV rosbags to convert ROS2 to ROS1
if [ ! -d "${CURRENT_DIR}/rosbags/" ]; then
    echo "Installing MapIV rosbags..."
    repo_url="https://github.com/MapIV/rosbags.git"
    git clone -b feature/ros2_to_ros1 --single-branch "${repo_url}"
    cd "${CURRENT_DIR}/rosbags/"
    python3 -m venv venv
    . venv/bin/activate

    pip install -r requirements-dev.txt
    pip install -e .
    deactivate

    echo "export ROSBAGS_VENV=\"${CURRENT_DIR}/rosbags/venv/\"" >> ~/.bashrc
    source ~/.bashrc

    cd "${CURRENT_DIR}"    

    echo "Done!"
fi

# Install ros2bag_extensions
if [ ! -d "${CURRENT_DIR}/extension_ws/install/" ]; then
    echo "Installing ros2bag_extensions..."
    # Create a workspace folder for the extensions
    if [ ! -d "${CURRENT_DIR}/extension_ws/src/" ]; then
        mkdir -p "${CURRENT_DIR}/extension_ws/src"
        # Clone extension package
        git clone https://github.com/tier4/ros2bag_extensions.git "${CURRENT_DIR}/extension_ws/src/"
    fi
    # build workspace
    cd "${CURRENT_DIR}/extension_ws/"
    source /opt/ros/humble/setup.bash
    rosdep install --from-paths . --ignore-src --rosdistro=${ROS_DISTRO}
    colcon build --symlink-install --catkin-skip-building-tests --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Release 

    grep -qxF "source \"${CURRENT_DIR}/extension_ws/install/setup.bash\"" ~/.bashrc || \
        echo "source \"${CURRENT_DIR}/extension_ws/install/setup.bash\"" >> ~/.bashrc

    cd "${CURRENT_DIR}"

    echo "Done!"
fi

# Install map4-cli
if ! command -v map4-cli >/dev/null 2>&1; then
    echo "Installing map4_engine..."
    echo "Adding a docker group"
    sudo groupadd -f docker
    if ! groups "${USER}" | grep -qw docker; then
        echo "Adding user group"
        sudo gpasswd -a "${USER}" docker
    fi

    if ! command -v pip3 >/dev/null 2>&1; then
        sudo apt update || true
        sudo apt install -y python3-pip
    fi

    unzip "${MAP4_PATH}/map4_engine.zip" -d "${MAP4_PATH}/"

    files=("${MAP4_PATH}"/map4_engine/map4-cli*.tar.gz)
    M4E_INSTALLER="${files[0]}"

    echo "${M4E_INSTALLER}"

    if [ ! -z "${M4E_INSTALLER}" ]; then
        pip3 install "${M4E_INSTALLER}"
    else
        echo "Error: No map4_engine installer was found. Abort..."
        exit 1
    fi

    echo 'export PATH=~/.local/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc
    echo "Initializing. Please input some information and wait (approx. 20min, depending on the network)."
    map4-cli init

    # Manually input some information here and wait for the installation to finish

    # Find the mount point of map4_engine output
    M4E_OUT_MOUNT="$(map4-cli show | jq -r '.output_mount')"
    echo "export M4E_OUT_MOUNT=\"${M4E_OUT_MOUNT}\"" >> ~/.bashrc

    echo "Done"
fi

# Install mapfourmer
# Unzip the .zip file
M4M_ZIP="$(ls -1 "${MAP4_PATH}"/mapfourmer-*.t4.zip 2>/dev/null | head -n 1)"
M4M_NAME="$(basename "${M4M_ZIP}" .t4.zip)"

echo $M4M_ZIP
echo $M4M_NAME

unzip "${M4M_ZIP}" -d "${MAP4_PATH}/"
M4M_DIR="${MAP4_PATH}/${M4M_NAME}/"

image_tag=$(basename "${M4M_DIR}"/mapfourmer-*.tar.zst .tar.zst)
image_tag="${image_tag#mapfourmer-}"

if ! docker image inspect "mapfourmer:${image_tag}" > /dev/null 2>&1; then
    echo "Installing mapfourmer ver ${image_tag}..."
    hash_=$(awk '{print $1 " " substr($2, match($2, /[^/]*$/))}' "${M4M_DIR}"/md5.hash)
    echo -e "Checking docker image version..."
    cd "${M4M_DIR}"
    if ! echo "$hash_" | md5sum -c; then
        echo -e "Failed"
        exit 1
    fi
    echo -e "Succeeded. Loading the docker image."
    zstd -d --stdout mapfourmer-*.tar.zst | docker load
    docker tag "mapfourmer:$image_tag" mapfourmer:latest
    cd "${CURRENT_DIR}"

    # Remove the unzipped folder
    rm -fr "${M4M_DIR}"
    echo "Done!"
fi

# Install yq to read/write YAML configuration file
if ! command -v yq >/dev/null 2>&1; then
    sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod a+x /usr/local/bin/yq
    echo "Installed yq version $(yq --version)"
fi

echo "# All necessary tools were installed successfully."

