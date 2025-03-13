// Copyright 2024 Autoware Foundation
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

#ifndef AUTOWARE__VOXEL_GRID_BUILDER_COMMON_HPP_
#define AUTOWARE__VOXEL_GRID_BUILDER_COMMON_HPP_

#include <functional>
#include <Eigen/Dense>

// This is for unordered_map and unordered_set of 2D/3D voxel grid
namespace std {

template <> struct hash<Eigen::Vector3i> {
public:
  size_t operator()(const Eigen::Vector3i &vid) const {
    std::size_t seed = 0;
    seed ^= std::hash<int>{}(vid(0)) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
    seed ^= std::hash<int>{}(vid(1)) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
    seed ^= std::hash<int>{}(vid(2)) + 0x9e3779b9 + (seed << 6) + (seed >> 2);

    return seed;
  }
};

} // namespace std

#endif