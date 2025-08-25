#!/bin/bash

set -eo pipefail
shopt -s nullglob

# Install all necessary tools for PCD map update
MAP4_PATH="$(dirname "$(readlink -f "$0")")"
WORKING_DIR="$(dirname "${MAP4_PATH}")"

# Install MapIV rosbags to convert ROS2 to ROS1
if [ ! -d "${WORKING_DIR}/rosbags/" ]; then
    echo -e "\nInstalling MapIV rosbags..."
    repo_url="https://github.com/MapIV/rosbags.git"
    git clone -b feature/ros2_to_ros1 --single-branch "${repo_url}"
    cd "${WORKING_DIR}/rosbags/"
    python3 -m venv venv
    . venv/bin/activate

    pip install -r requirements-dev.txt
    pip install -e .
    deactivate

    echo "export ROSBAGS_VENV=\"${WORKING_DIR}/rosbags/venv/\"" >> ~/.bashrc
    source ~/.bashrc

    cd "${WORKING_DIR}"    

    echo "Done!"
fi

# Install ros2bag_extensions
if [ ! -d "${WORKING_DIR}/extension_ws/install/" ]; then
    echo -e "\nInstalling ros2bag_extensions..."
    # Create a workspace folder for the extensions
    if [ ! -d "${WORKING_DIR}/extension_ws/src/" ]; then
        mkdir -p "${WORKING_DIR}/extension_ws/src"
        # Clone extension package
        git clone https://github.com/tier4/ros2bag_extensions.git "${WORKING_DIR}/extension_ws/src/"
    fi
    # build workspace
    cd "${WORKING_DIR}/extension_ws/"
    source /opt/ros/humble/setup.bash
    rosdep install --from-paths . --ignore-src --rosdistro=${ROS_DISTRO}
    colcon build --symlink-install --catkin-skip-building-tests --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Release 

    grep -qxF "source \"${WORKING_DIR}/extension_ws/install/setup.bash\"" ~/.bashrc || \
        echo "source \"${WORKING_DIR}/extension_ws/install/setup.bash\"" >> ~/.bashrc

    cd "${WORKING_DIR}"

    echo "Done!"
fi

# Install map4-cli and map4_engine
if ! command -v map4-cli >/dev/null 2>&1; then
    echo -e "\nInstalling map4_engine..."
    sudo groupadd -f docker
    if ! groups "${USER}" | grep -qw docker; then
        echo "Adding user group"
        sudo gpasswd -a "${USER}" docker
    fi

    if ! command -v pip3 >/dev/null 2>&1; then
        sudo apt update || true
        sudo apt install -y python3-pip
    fi

    if [ ! -d "${MAP4_PATH}/map4_engine/" ]; then
        if [ ! -f "${MAP4_PATH}/map4_engine.zip" ]; then
            echo "Error: No map4_engine.zip package was found. Abort..."
            exit 1
        fi

        unzip "${MAP4_PATH}/map4_engine.zip" -d "${MAP4_PATH}/"
    fi

    files=("${MAP4_PATH}"/map4_engine/map4-cli*.tar.gz)
    M4E_INSTALLER="${files[0]:-}"

    if [ ! -z "${M4E_INSTALLER}" ]; then
        pip3 install "${M4E_INSTALLER}"
    else
        echo "Error: No map4_engine installer was found. Abort..."
        exit 1
    fi

    grep -qF 'export PATH=~/.local/bin:$PATH' ~/.bashrc ||
        echo 'export PATH=~/.local/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc
    echo "Initializing. Please input some information and wait (approx. 10min, depending on the network)."
    map4-cli init

    # Manually input some information here and wait for the installation to finish

    # Find the mount point of map4_engine output
    M4E_OUT_MOUNT="$(map4-cli show | sed -n '/^{/,/^}/p' | jq -r '.output_mount')"
    echo "export M4E_OUT_MOUNT=\"${M4E_OUT_MOUNT}\"" >> ~/.bashrc

    # Copy the config file to the output mount folder
    image="$(docker images --format '{{.Repository}}:{{.Tag}}' \
        | grep "map4_engine_ui_nvidia" \
        | sort -t: -k2 -V\
        | tail -n1)"

    read username password user_id group_id tag <<< \
        $(map4-cli show | sed -n '/^{/,/^}/p' | \
        jq -r '[.username, .password, .user_id, .group_id, .tag] | @tsv')

    docker run -it --rm \
        --env "AWS_USERNAME=${username}" \
        --env "AWS_PASSWORD=${password}" \
        --env "USER_ID=${user_id}" \
        --env "GROUP_ID=${group_id}" \
        --env "M4E_TAG=${tag}" \
        -v "${M4E_OUT_MOUNT}":/mnt/output/:rw \
        ${image} cp /home/guest/map4_engine/config/map4_engine.yaml /mnt/output/map4_engine.yaml

    echo "Done"
fi

# Install mapfourmer
# Unzip the .zip file
M4M_ZIP="$(ls -1 "${MAP4_PATH}"/mapfourmer-*.t4.zip 2>/dev/null | head -n 1)"
M4M_NAME="$(basename "${M4M_ZIP}" .t4.zip)"

M4M_DIR="${MAP4_PATH}/${M4M_NAME}/"
image_tag="${M4M_NAME#mapfourmer-}"

if ! docker image inspect "mapfourmer:${image_tag}" > /dev/null 2>&1; then
    echo -e "\nInstalling mapfourmer ver ${image_tag}..."
    unzip "${M4M_ZIP}" -d "${MAP4_PATH}/"
    hash_=$(awk '{print $1 " " substr($2, match($2, /[^/]*$/))}' "${M4M_DIR}"/md5.hash)
    echo "Checking the docker image version..."
    cd "${M4M_DIR}"

    if ! echo "$hash_" | md5sum -c ; then
        echo -e "Failed"
        exit 1
    fi

    echo -e "Succeeded. Loading the docker image."
    zstd -d --stdout mapfourmer-*.tar.zst | docker load
    docker tag "mapfourmer:$image_tag" mapfourmer:latest
    cd "${WORKING_DIR}"

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

shopt -u nullglob

# Install point cloud divider and point cloud merger
if [ ! -d "${WORKING_DIR}/autoware/install/autoware_pointcloud_divider/" ]; then
    echo -e "\nInstalling autoware_pointcloud_divider..."
    cd "${WORKING_DIR}/autoware/"

    if [ ! -d "src/tools/map/autoware_pointcloud_divider" ]; then
        vcs import src < tools.repos
    fi

    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release \
            --packages-up-to=autoware_pointcloud_divider
    cd "${WORKING_DIR}"
    echo "Done!"
fi

if [ ! -d "${WORKING_DIR}/autoware/install/autoware_pointcloud_merger/" ]; then
    echo -e "\nInstalling autoware_pointcloud_merger..."
    cd "${WORKING_DIR}/autoware/"

    if [ ! -d "src/tools/map/autoware_pointcloud_divider" ]; then
        vcs import src < tools.repos
    fi

    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release \
            --packages-up-to=autoware_pointcloud_merger
    cd "${WORKING_DIR}"
    echo "Done!"
fi

source "${WORKING_DIR}/autoware/install/setup.bash"

echo "# All necessary tools were installed successfully."
echo -e "# A sample config YAML file can be found at \n${M4E_OUT_MOUNT}/map4_engine.yaml"


