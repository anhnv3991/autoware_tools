# autoware_pointcloud_merger

This is a tool for checking a PCD map fulfills the PCD Map creation requirement:

## Installation

```bash
cd <PATH_TO_pilot-auto.*> # OR <PATH_TO_autoware>
cd src/
git clone git@github.com:autowarefoundation/autoware_tools.git
cd ..
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release --catkin-skip-building-tests --symlink-install --packages-up-to=autoware_pcd_checker
```

## Usage

  ```bash
  ros2 launch autoware_pcd_checker pointcloud_merger.launch.xml map_path:=<MAP_PATH>
  ```

  | Name       | Description                                 |
  | ---------- | ------------------------------------------- |
  | INPUT_DIR  | Directory that contains all input PCD files |
  | OUTPUT_PCD | Name of the output PCD file                 |

`INPUT_DIR` and `OUTPUT_PCD` should be specified as **absolute paths**.

## Parameter

{{ json_to_markdown("map/autoware_pointcloud_merger/schema/pointcloud_merger.schema.json") }}

## LICENSE

Parts of files pcd_merger.hpp, and pcd_merger.cpp are copied from [MapIV's pointcloud_divider](https://github.com/MapIV/pointcloud_divider) and are under [BSD-3-Clauses](LICENSE) license. The remaining code are under [Apache License 2.0](../../LICENSE)
