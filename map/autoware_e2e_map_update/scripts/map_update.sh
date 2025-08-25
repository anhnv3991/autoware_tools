#!/bin/bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <path_to_the_ROS2_rosbag_folder> <path_to_the_old_map_folder> <path_to_the_new_map_folder>" 
    exit 1
fi

# Run mapfourmer
mapfourmer_run() {
  input=$1
  output=$2
  username=$3
  password=$4

  # The below scripts are copied from the MapIV mapfourmer run.sh
  endpoint="https://i97189rgp4.execute-api.ap-northeast-1.amazonaws.com/prod/user/allowed-features"

  status_code=$(curl --fail --silent -X POST \
  -o /dev/null -w '%{http_code}' \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$username\", \"password\":\"$password\"}" \
  $endpoint 2>/dev/null)

  case "$status_code" in
  200)
    echo "Authorization succeeded!"
    ;;
  404)
    echo "Could not found the username ${username}"
    exit 1
    ;;
  401)
    echo "Invalid username or password"
    exit 1
    ;;
  *)
    echo "An unexpected error has occurred. Please check your internet connection!"
    exit 1
    ;;
  esac

  docker_volume=""
  docker_volume="${docker_volume} -v /tmp/.X11-unix:/tmp/.X11-unix:rw"
  docker_volume="${docker_volume} -v /etc/fstab:/home/fstab:ro"
  docker_volume="${docker_volume} -v ${HOME}:${HOME}:rw"
  docker_volume="${docker_volume} -v /media:/media:rw"

  echo "docker_volume = ${docker_volume}"

  # We may run into symbolic link, which cannot be read from docker images
  # Hence, we need the actual path to the script
  SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

  echo "Script dir = ${SCRIPT_DIR}"
  echo "input = ${input}"
  echo "output = ${output}"
  echo "${DISPLAY}"

  # Run mapfourmer docker 

  # Run mapfourmer docker 
  docker run \
    --rm -it \
      --gpus all \
      --env "DISPLAY=${DISPLAY}" \
      --privileged \
      --shm-size=20gb \
      --net host \
      --workdir "/mapfourmer" \
      ${docker_volume} \
      --user "$(id -u):$(id -g)" \
      --name "mapfourmer" \
      --entrypoint "" \
      --env "AWS_USERNAME=${username}" \
      --env "AWS_PASSWORD=${password}" \
      --env "M4E_ENV=prod" \
      --env "M4E_SIZE=0" \
      --env "M4E_CMD=Mapfourmer" \
      --env "M4E_PRODUCT=mapfourmer" \
      -v "${SCRIPT_DIR}":/mapfourmer/host_scripts:rw \
      -v "${input}":/mapfourmer/input/:rw \
      -v "${output}":/mapfourmer/output/:rw \
      mapfourmer:latest \
      bash host_scripts/mapfourmer.sh "/mapfourmer/input" "/mapfourmer/output"
}

BAG_DIR_PATH=$1
OLD_MAP_PATH=$2
NEW_MAP_PATH=$3
TMP_DIR="${NEW_MAP_PATH}/tmp_dir/"
TMP_BAG_DIR="${TMP_DIR}/rosbag/"
TMP_MAP_DIR="${TMP_DIR}/map/"
ROS2_MERGED_BAG_PATH="${TMP_BAG_DIR}/merged.db3"
MAP4_INPUT_DIR="${M4E_OUT_MOUNT}/input/"
MAP4_INPUT_BAG="${MAP4_INPUT_DIR}/input.bag"
MAP4_INPUT_MAP="${MAP4_INPUT_DIR}/map.pcd"
MAP4_OUTPUT_DIR="${M4E_OUT_MOUNT}/output/"
INPUT_CONFIG="${M4E_OUT_MOUNT}/map4_engine.yaml"
WORKING_DIR="$(basename "$(dirname "$(readlink -f "$0")")")"

################ STEP 1: Rosbag pre-processing  ############
# Check if the input folders and files exist
if [ ! -d "${BAG_DIR_PATH}" ]; then
    echo "Error: the rosbag folder ${BAG_DIR_PATH} does not exist."
    exit 2
fi

if [ ! -d "${OLD_MAP_PATH}" ]; then
    echo "Error: the old map folder ${OLD_MAP_PATH} does not exist."
    exit 2
fi

if [ ! -f "${INPUT_CONFIG}" ]; then
    echo "Error: the config file at ${INPUT_CONFIG} does not exist."
    exit 2
fi

# Create the tmp directories, for storing the intermediate files
mkdir -p "${TMP_DIR}"
mkdir -p "${TMP_BAG_DIR}"
mkdir -p "${TMP_MAP_DIR}"
mkdir -p "${MAP4_INPUT_DIR}"
mkdir -p "${MAP4_OUTPUT_DIR}"

# Create the output directory 
if [ -d "${MAP4_OUTPUT_DIR}" ]; then
    rm -fr "${MAP4_OUTPUT_DIR}"
fi
mkdir -p "${MAP4_OUTPUT_DIR}"

# Copy the config YAML file to map4 input directory
MAP4_CONFIG="${MAP4_INPUT_DIR}/map4_engine.yaml"
cp "${INPUT_CONFIG}" "${MAP4_CONFIG}"

SENSOR_TOPIC="$(yq '.lidar[0].topic' ${MAP4_CONFIG})"
IMU_TOPIC="$(yq '.imu[0].topic' ${MAP4_CONFIG})"
GNSS_TOPIC="$(yq '.gnss[0].topic' ${MAP4_CONFIG})"

# Find all .db3 files in the bag folder
echo "# Step 1: Data pre-processing"

# Step 1: rosbag pre-processing
# Ask if users want to delete old rosbag files
# If no, then this step is skipped
if [ -f "${MAP4_INPUT_BAG}" ]; then
    echo "A rosbag already exists at ${MAP4_INPUT_BAG}. Do you want to re-create it (y/n)?: "
    read choice
    choice="${choice:0:1}"
    echo ""
else 
    choice="y"
fi

if [ "y" == "${choice}" ]; then
    # Try to re-create the input ROS1 rosbag
    # Check if the tmp ROS2 rosbag already exist
    if [ -z "$(find ${TMP_BAG_DIR} -mindepth 1 -print -quit)" ]; then
        echo "The folder ${TMP_BAG_DIR} is not empty. Do you want to delete all of its content (y/n)?:"
        read choice
        choice="${choice:0:1}"
        echo ""
    else
        choice="y"
    fi

    # If users want to delete all tmp rosbags, or the tmp rosbags have not been created yet
    if [ "y" == "${choice}" ]; then
        # Delete all tmp ROS2 rosbags
        find "${TMP_BAG_DIR}" -mindepth 1 -delete

        # Re-do the preprocessing ROS2 rosbag
        # Find the input ROS2 rosbags
        ROS2_BAG_LIST=()
        for BAG_FILE in "${BAG_DIR_PATH}"/*."db3"; do
            ROS2_BAG_LIST+=("${BAG_FILE}")
        done

        echo -e "\nFound ${#ROS2_BAG_LIST[@]} rosbags. Filtering...\n"

        # Filter all input .db3 files
        # The filtered files are saved in the TMP directory
        FILTERED_ROS2_BAG_LIST=()
        for BAG_FILE in "${ROS2_BAG_LIST[@]}"; do
            # The filtered bag name is the old bag with a prefix "filtered_"
            filename=$(basename "${BAG_FILE}")
            filtered_name="${TMP_BAG_DIR}/filtered_${filename}"

            echo "Filtering ${filename}"

            ros2 bag filter -o "${filtered_name}" "${BAG_FILE}" -i \
                "${IMU_TOPIC}" "${GNSS_TOPIC}" "${SENSOR_TOPIC}" >/dev/null 2>&1 # Hide the output

            FILTERED_ROS2_BAG_LIST+=("${filtered_name}")
        done

        echo -e "\nFiltered ${#FILTERED_ROS2_BAG_LIST[@]} rosbags. Merging all...\n"

        # Merge all rosbags to a single one
        ros2 bag merge -o "${ROS2_MERGED_BAG_PATH}" "${FILTERED_ROS2_BAG_LIST}"

        # Let's stop here to check
        echo -e "\nFinished merging.\n"
    fi

    # Convert the ROS2 merged rosbag to ROS1 format
    # Activate venv 
    source "${ROSBAGS_VENV}/bin/activate"

    rosbags-convert-2to1 "${ROS2_MERGED_BAG_PATH}" >/dev/null 2>&1
    # Move the converted ROS1 bag to the data directory
    mv "${ROS2_MERGED_BAG_PATH}".bag "${MAP4_INPUT_BAG}"
    # Deactivate venv
    deactivate

    echo -e "\nDone."
fi

echo "map4 input map = ${MAP4_INPUT_MAP}"

if [ -f "${MAP4_INPUT_MAP}" ]; then
    echo "An input PCD map for map4_engine already exists at ${MAP4_INPUT_MAP}. Do you want to re-create? (y/n):"
    read choice
    choice="${choice:0:1}"
    echo ""
else
    choice="y"
fi

if [ "y" == "${choice}" ]; then
    # Merge the PCD maps to a single file for faster processing
    echo "Combining PCD files"
    ros2 launch autoware_pointcloud_merger pointcloud_merger.launch.xml \
        input_pcd_dir:="${OLD_MAP_PATH}" \
        output_pcd:="${MAP4_INPUT_MAP}" > /dev/null

    # For debug
    echo -e "Done."
fi

################ STEP 2: Map Update  ############
echo "# Step 2: Map Update"
# Clean the tmp output directory at MAP4_INPUT_DIR/output
mkdir -p "${MAP4_OUTPUT_DIR}"
find "${MAP4_OUTPUT_DIR}" -mindepth 1 -delete

# Set the output files of point cloud update and mapfourmer to LAS
# Processing PCD by mapfourmer often results in errors, while using LAS does not
# 0: PCD, 1: LAS, 2: PLY
yq e '.pcd2x.file_format = 1' -i "${MAP4_CONFIG}"

# Update the old map
echo "Updating PCD map..."
read username password user_id group_id tag <<< \
    $(map4-cli show | sed -n '/^{/,/^}/p' | \
    jq -r '[.username, .password, .user_id, .group_id, .tag] | @tsv')

image="$(docker images --format '{{.Repository}}:{{.Tag}}' \
        | grep "map4_engine_ui_nvidia" \
        | sort -t: -k2 -V\
        | tail -n1)"

docker run -it --rm \
    --env "AWS_USERNAME=${username}" \
    --env "AWS_PASSWORD=${password}" \
    --env "USER_ID=${user_id}" \
    --env "GROUP_ID=${group_id}" \
    --env "M4E_TAG=${tag}" \
    --runtime=nvidia \
    -v "${M4E_OUT_MOUNT}"/:/data/ ${image} \
    scripts/pointcloud_update/scan2map.sh \
    -o /data/output/ \
    /data/input/ \
    /data/input/ \
    /data/input/map4_engine.yaml \
    /home/guest/map4_engine/lidar_calib

# Now the new map is stored in the folder ${MAP4_OUTPUT_DIR}/update_map/
# Run mapfourmer to clean the map from dynamic points
echo -e "\nDone. Removing dynamic points..."

# Create a directory for cleaning PCD files
mkdir -p "${MAP4_OUTPUT_DIR}/clean/"
# Make sure it is empty
find "${MAP4_OUTPUT_DIR}/clean/" -mindepth 1 -delete

mapfourmer_run "${MAP4_OUTPUT_DIR}/update_map/" "${MAP4_OUTPUT_DIR}/clean/" "${username}" "${password}"

# Convert the LAS files to PCD format
yq e '.pcd2x.file_format = 0' -i "${MAP4_CONFIG}"

docker run -it --rm \
    --env "AWS_USERNAME=${username}" \
    --env "AWS_PASSWORD=${password}" \
    --env "USER_ID=${user_id}" \
    --env "GROUP_ID=${group_id}" \
    --env "M4E_TAG=${tag}" \
    -v "${M4E_OUT_MOUNT}"/:/data/  "${image}" \
    scripts/pcd/x2x.sh \
    /data/output/clean/non-noise/input/ \
    /data/map4_engine.yaml 

################ STEP 3: Post Validation  ############
# Use CloudCompare, please!
# Visualizing thousands small PCD files is quite troublesome
# This command merges all small PCD files to a single big one, 
# which is easier to visualize by CloudCompare
ros2 launch autoware_pointcloud_merger pointcloud_merger.launch.xml \
    input_pcd_dir:="${MAP4_OUTPUT_DIR}/clean/non-noise/input/" \
    output_pcd:="${MAP4_OUTPUT_DIR}/merged.pcd" > /dev/null

echo "The update is finished. Please check the updated map at ${MAP4_OUTPUT_DIR}/merged.pcd"

echo -e "Do you feel satisfied with the updated map. \
        If you do, all of the tmp files would be deleted, and the updated PCD map \
        will be segmented by autoware point cloud divider and put at \n \
        ${NEW_MAP_PATH}. \n \
        If you do not, the tmp files would still remain, and you can adjust parameters \
        in the config file at \n \
        ${MAP4_CONFIG} \n
        to achieve better update quality. \
        Enter your choice (y/n):"

read choice
choice="${choice:0:1}"
echo ""

if [ "y" == "${choice}" ]; then
    # After finished, run the pointcloud divider on the clean files
    ros2 launch autoware_pointcloud_divider pointcloud_divider.launch.xml \
        input_pcd_or_dir:="${MAP4_OUTPUT_DIR}/clean/non-noise/input/" \
        output_pcd_dir:="${NEW_MAP_PATH}" \
        leaf_size:=0.2  \
        prefix:=new

    # Remove the tmp directory
    rm -fr "${TMP_DIR}"

    # Remove all intermediate files
    rm -fr "${MAP4_INPUT_DIR}"
    rm -fr "${MAP4_OUTPUT_DIR}"

    echo -e "The PCD map update is now completed. Please get the updated files at \n ${NEW_MAP_PATH}"
else
    echo "Since the updated quality is not good, please check your data and adjust parameters at \n ${MAP4_CONFIG}"
fi

cd "${WORKING_DIR}"