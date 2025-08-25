#!/bin/bash

WORKING_DIR="$(basename "$(pwd)")"

# Remove MapIV rosbags
if [ -d "${WORKING_DIR}/rosbags/" ]; then
    echo -ne "\nDo you want to remove the rosbags tool? (y/n):"
    read choice
    choice="${choice:0:1}"
    echo ""

    if [ "y" == "${choice}" ] || [ "Y" == "${choice}" ]; then
        echo -ne "\nRemoving MapIV rosbags..."
        rm -fr "${WORKING_DIR}/rosbags/"
        grep -q '^export ROSBAGS_VENV=' ~/.bashrc && \
            sed -i '/^export ROSBAGS_VENV=/d' ~/.bashrc 
        echo "Done!"
    fi
fi

# Remove rosbags extension
if [ -d "${WORKING_DIR}/extension_ws/" ]; then
    echo -ne "\nDo you want to remove the rosbag extensions? (y/n):"
    read choice
    choice="${choice:0:1}"
    echo ""

    if [ "y" == "${choice}" ] || [ "Y" == "${choice}" ]; then
        echo -ne "\nRemoving rosbag extension..."
        grep -qF "extension_ws/install/setup.bash" ~/.bashrc && \
            sed -i '\|/extension_ws/install|d' ~/.bashrc
        rm -fr "${WORKING_DIR}/extension_ws/"
        echo "Done!"
    fi
fi

# Remove map4-cli and map4_engine
if command -v map4-cli >/dev/null 2>&1; then
    echo -ne "\nDo you want to remove map4-cli and map4_engine (y/n)?: "
    read choice
    choice="${choice:0:1}"
    echo ""

    if [ "y" == "${choice}" ] || [ "Y" == "${choice}" ]; then
        echo -ne "\nRemoving map4-cli..."
        pip3 uninstall map4-cli
        docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" \
            | grep "map4_engine" \
            | awk '{print $2}' \
            | xargs -r docker rmi -f        
        grep -qF 'export PATH=~/.local/bin:$PATH' ~/.bashrc &&
            sed -i '\|export PATH=~/.local/bin:$PATH|d' ~/.bashrc
        grep -qF 'M4E_OUT_MOUNT' ~/.bashrc && \
            sed -i '/M4E_OUT_MOUNT/d' ~/.bashrc
        echo "Done!"
    fi    
fi

# Remove mapfourmer
if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q 'mapfourmer'; then
    echo -ne "\nDo you want to remove mapfourmer (y/n)?: "
    read choice
    choice="${choice:0:1}"
    echo ""

    if [ "y" == "${choice}" ] || [ "Y" == "${choice}" ]; then
        echo -ne "\nRemoving mapfourmer..."
        docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" \
            | grep "mapfourmer" \
            | awk '{print $2}' \
            | xargs -r docker rmi -f
        echo "Done!"
    fi
fi

echo -e "\n# All tools were removed successfully."