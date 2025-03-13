#ifndef AUTOWARE__VOXEL_GRID_BUILDER_HPP_
#define AUTOWARE__VOXEL_GRID_BUILDER_HPP_

#include <iostream>
#include <fstream>
#include <string>
#include <vector>

#include <Eigen/Dense>
#include <Eigen/Cholesky>

#include <pcl/point_types.h>
#include <pcl/point_cloud.h>

namespace autoware::voxel_grid_builder
{

template <typename PointT>
class VoxelGridBuilder
{
    using PclCloudType = pcl::PointCloud<PointT>;
    using PclCloudPtr = typename PclCloudType::Ptr;
    using PclCloudConstPtr = typename PclCloudType::ConstPtr;

public:

    struct Leaf {
        Leaf();
        Leaf(const Leaf&);
        Leaf(Leaf&&);
        Leaf& operator=(const Leaf&);
        Leaf& operator=(Leaf&&);

        void to_binary(std::ostream & os);
        void from_binary(std::istream & is);

        int nr_points_;
        Eigen::VectorXf centroid_;
        Eigen::Matrix3d icov_;
    };

    // Read the input PCDs, build the NDT structures, and save to files in the output directory
    void build(const std::string & pcd_path, const std::string & ndt_path);

    // For setting voxel grid parameters
    void setResolution(float res) { resolution_ = res; }
    void setMinPointsPerVoxel(int val) { min_points_per_voxel_ = val; }
    
    float getResolution() const { return resolution_; }
    int getMinPointsPerVoxel() const { return min_points_per_voxel_; }
    double getMinCovEvalMult() const { return min_cov_eval_mult_; }

private:
    void applyFilter(const PclCloudConstPtr & input, std::ofstream & output_path);
    void updateLeaf(Leaf& leaf, const PointT & p);
    // Compute the mean and inverse covariance of 
    bool computeLeafParams(Eigen::SelfAdjointEigenSolver<Eigen::Matrix3d> &eigensolver, Leaf &leaf);

    std::vector<std::string> discoverPCDs(const std::string & pcd_dir_or_file);

    float resolution_;
    int min_points_per_voxel_;
    double min_cov_eval_mult_;
};

}

#endif