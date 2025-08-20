# autoware_e2e_map_update

Here are a script that wraps all tools required to update a PCD map. We can now update PCD by just running this script. No need to run individual steps manually.

## Installing necessary tools

```bash

```

## Usage
- Prepare the input data, including the ROS2 rosbags, old PCD maps
- Run the install.sh script
  ```bash
  ros2 run autoware_e2e_map_update install.sh <path_to_installation_dir>
  ```
    | Name               | Description                                                                  |
  | ------------------ | ---------------------------------------------------------------------------- |
  | path_to_installation_dir    | The directory containing the map4_engine.zip and the mapfourmer.zip file                           |
- Edit the map4_engine.yaml file 
- Run this script

  ```bash
  ros2 run autoware_e2e_map_update map_update.sh <path_to_bag_dir> <path_to_old_map> <path_to_config> 
  ```

  | Name               | Description                                                                  |
  | ------------------ | ---------------------------------------------------------------------------- |
  | path_to_bag_dir    | The directory that contains the input ROS2 rosbags                           |
  | path_to_old_map    | The directory that contains the old PCD map files                            |
  | path_to_config     | The path to the map4_engine.yaml file                                        |
  | cred_file          | The credential file containing the username and password of mapfourmer       |

  Paths to folders and files should be specified as **absolute paths**.

## Parameter

{{ json_to_markdown("map/autoware_e2e_map_update/schema/map_update.schema.json") }}

## LICENSE

This package is under [Apache License 2.0](../../LICENSE)
