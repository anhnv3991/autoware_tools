// Copyright 2025 Autoware Foundation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "include/voxel_grid_builder_node.hpp"

#include <autoware/voxel_grid_builder/voxel_grid_builder.hpp>

#include <pcl/point_types.h>

#include <string>

namespace autoware::voxel_grid_builder
{

VoxelGridBuilderNode::VoxelGridBuilderNode(const rclcpp::NodeOptions & node_options)
: Node("voxel_grid_builder_node", node_options)
{
    std::string input_pcd_or_dir = declare_parameter<std::string>("input_pcd_or_dir");
    std::string output_dir = declare_parameter<std::string>("output_dir");
    std::string point_type = declare_parameter<std::string>("point_type");

    fprintf(stderr, "######## Input Parameters ########\n");
    fprintf(stderr, "\tinput_pcd_or_dir: %s\n", input_pcd_or_dir.c_str());
    fprintf(stderr, "\toutput_dir: %s\n", output_dir.c_str());
    fprintf(stderr, "\tpoint_type: %s\n", point_type.c_str());

    if (point_type == "point_xyz") {
        autoware::voxel_grid_builder::VoxelGridBuilder<pcl::PointXYZ> vg_builder;

        vg_builder.build(input_pcd_or_dir, output_dir);
    } else if (point_type == "point_xyzi") {
        autoware::voxel_grid_builder::VoxelGridBuilder<pcl::PointXYZI> vg_builder;

        vg_builder.build(input_pcd_or_dir, output_dir);
    }

    rclcpp::shutdown();
}   // namespace autoware::voxel_grid_builder

}

#include <rclcpp_components/register_node_macro.hpp>

RCLCPP_COMPONENTS_REGISTER_NODE(autoware::voxel_grid_builder::VoxelGridBuilderNode)