#include <filesystem>
#include <memory>
#include <unordered_map>

#include <pcl/io/pcd_io.h>

#include <autoware/voxel_grid_builder/common.hpp>
#include <autoware/voxel_grid_builder/voxel_grid_builder.hpp>


namespace fs = std::filesystem;

namespace autoware::voxel_grid_builder
{

template <typename PointT>
VoxelGridBuilder<PointT>::Leaf::Leaf() 
: nr_points_(0),
    centroid_(Eigen::Vector3f::Zero()),
    icov_(Eigen::Matrix3f::Identity()),
    first_(Eigen::Vector3f::Zero())
{}

template <typename PointT>
VoxelGridBuilder<PointT>::Leaf::Leaf(const Leaf & other)
: nr_points_(other.nr_points_),
    centroid_(other.centroid_),
    icov_(other.icov_),
    first_(other.first_)
{}

template <typename PointT>
VoxelGridBuilder<PointT>::Leaf::Leaf(Leaf && other)
: nr_points_(other.nr_points_),
    centroid_(std::move(other.centroid_)),
    icov_(std::move(other.icov_)),
    first_(std::move(other.first_))
{}

template <typename PointT>
typename VoxelGridBuilder<PointT>::Leaf & VoxelGridBuilder<PointT>::Leaf::operator=(const Leaf & other)
{
    nr_points_ = other.nr_points_;
    centroid_ = other.centroid_;
    icov_ = other.icov_;
    first_ = other.first_;
    
    return *this;
}

template <typename PointT>
typename VoxelGridBuilder<PointT>::Leaf & VoxelGridBuilder<PointT>::Leaf::operator=(Leaf && other)
{
    nr_points_ = other.nr_points_;
    centroid_ = std::move(other.centroid_);
    icov_ = std::move(other.icov_);
    first_ = std::move(other.first_);

    return *this;
}

template <typename PointT>
void VoxelGridBuilder<PointT>::Leaf::to_binary(std::ostream & os)
{
    // No need to stores the number of points
    os.write((char*)&(centroid_[0]), sizeof(typename decltype(centroid_)::Scalar));
    os.write((char*)&(centroid_[1]), sizeof(typename decltype(centroid_)::Scalar));
    os.write((char*)&(centroid_[2]), sizeof(typename decltype(centroid_)::Scalar));

    // The inverse covariance is symmetric, so only storing upper half is OK
    for (int i = 0; i < 3; ++i) {
        for (int j = i; j < 3; ++j) {
            os.write((char*)&(icov_(i, j)), sizeof(typename decltype(icov_)::Scalar));
        }
    }
}

template <typename PointT>
void VoxelGridBuilder<PointT>::Leaf::from_binary(std::istream & is)
{
    // is.read((char*)&nr_points_, sizeof(decltype(nr_points_)));
    is.read((char*)&(centroid_[0]), sizeof(typename decltype(centroid_)::Scalar));
    is.read((char*)&(centroid_[1]), sizeof(typename decltype(centroid_)::Scalar));
    is.read((char*)&(centroid_[2]), sizeof(typename decltype(centroid_)::Scalar));

    for (int i = 0; i < 3; ++i) {
        for (int j = 1; j < 3; ++j) {
            is.read((char*)&(icov_(i, j)), sizeof(typename decltype(icov_)::Scalar));
        }
    }

    icov_(1, 0) = icov_(0, 1);
    icov_(2, 0) = icov_(0, 2);
    icov_(2, 1) = icov_(1, 2);
}

template <typename PointT>
VoxelGridBuilder<PointT>::VoxelGridBuilder()
: resolution_(2.0),
    min_points_per_voxel_(6),
    min_cov_eval_mult_(0.01)
{}

template <typename PointT>
std::vector<std::string> VoxelGridBuilder<PointT>::discoverPCDs(const std::string &pcd_dir_or_file)
{
    // Full paths to the PCD files
    std::vector<std::string> pcd_list;
    fs::path input_path(pcd_dir_or_file);

    if (fs::is_directory(input_path)) {
        fprintf(stdout, "Input PCD directory: %s\n", input_path.c_str());

        for (auto & entry : fs::directory_iterator(input_path)) {
            if (fs::is_regular_file(entry.symlink_status())) {
                auto ext = entry.path().extension().string(); 

                if (ext == ".pcd" || ext == ".PCD") {
                    pcd_list.push_back(entry.path().string());
                }
            }
        }
    } else if (fs::is_regular_file(input_path)) {
        auto file_name = input_path.string();
        auto ext = input_path.extension().string();

        if (ext == ".pcd" || ext == ".PCD") {
            fprintf(stdout, "Input PCD file: %s\n", file_name.c_str());
            pcd_list.push_back(file_name);
        } else {
            fprintf(stderr, "Error: The input file is not PCD format %s\n", file_name.c_str());
            exit(EXIT_FAILURE);
        }
    } else {
        fprintf(stderr, "Error: Unknown input %s\n", input_path.c_str());
        exit(EXIT_FAILURE);
    }

    return pcd_list;
}

template <typename PointT>
void VoxelGridBuilder<PointT>::applyFilter(const PclCloudConstPtr & input, std::ofstream & os)
{
    if (!input) {
        fprintf(stderr, "Error: The pointer to the input cloud is nullptr.\n");
        exit(EXIT_FAILURE);
    }

    // Phase 0: distribute points to leaves
    std::unordered_map<Eigen::Vector3i, Leaf> voxel_grid;

    for (auto & p : *input) {
        if (!input->is_dense) {
            if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z)) {
                continue;
            }
        }
        Eigen::Vector3i vid;

        vid(0) = static_cast<int>(floor(p.x / resolution_));
        vid(1) = static_cast<int>(floor(p.y / resolution_));
        vid(2) = static_cast<int>(floor(p.z / resolution_));

        Leaf& leaf = voxel_grid[vid];

        updateLeaf(leaf, p);
    }

    Eigen::SelfAdjointEigenSolver<Eigen::Matrix3f> eigensolver;

    // Phase 1: compute inverse covariance of leaves
    for (auto & voxel : voxel_grid) {
        if (voxel.second.nr_points_ >= min_points_per_voxel_) {
            computeLeafParams(eigensolver, voxel.second);
        } else {
            voxel.second.centroid_[0] = std::numeric_limits<typename std::remove_reference<decltype(voxel.second.centroid_(0))>::type>::infinity();
        }

        voxel.second.to_binary(os);
    }
}

template <typename PointT>
void VoxelGridBuilder<PointT>::updateLeaf(Leaf & leaf, const PointT & p)
{
    if (leaf.nr_points_ == 0) {
        leaf.first_(0) = p.x;
        leaf.first_(1) = p.y;
        leaf.first_(2) = p.z;
    }

    float dx = p.x - leaf.first_(0);
    float dy = p.y - leaf.first_(1);
    float dz = p.z - leaf.first_(2);

    leaf.icov_(0, 0) += dx * dx;
    leaf.icov_(0, 1) += dx * dy;
    leaf.icov_(0, 2) += dx * dz;
    leaf.icov_(1, 1) += dy * dy;
    leaf.icov_(1, 2) += dy * dz;
    leaf.icov_(2, 2) += dz * dz;

    leaf.centroid_[0] += dx;
    leaf.centroid_[1] += dy;
    leaf.centroid_[2] += dz;
    ++leaf.nr_points_;
}

template <typename PointT>
void VoxelGridBuilder<PointT>::
computeLeafParams(Eigen::SelfAdjointEigenSolver<Eigen::Matrix3f> &eigensolver, Leaf &leaf)
{
    // Get sum of points
    double sx = leaf.centroid_[0], sy = leaf.centroid_[1], sz = leaf.centroid_[2];
    // Get double-casted number of points
    double n = leaf.nr_points_, n_minus_one = n - 1.0;
    double mx = sx / n, my = sy / n, mz = sz / n;

    // Compute the mean of points
    leaf.centroid_[0] = mx + leaf.first_(0);
    leaf.centroid_[1] = my + leaf.first_(1);
    leaf.centroid_[2] = mz + leaf.first_(2);

    // Compute the covariance matrix
    leaf.icov_(0, 0) = (leaf.icov_(0, 0) - sx * mx) / n_minus_one;
    leaf.icov_(1, 0) = leaf.icov_(0, 1) = (leaf.icov_(0, 1) - sx * my) / n_minus_one;
    leaf.icov_(2, 0) = leaf.icov_(0, 2) = (leaf.icov_(0, 2) - sx * mz) / n_minus_one;
    leaf.icov_(1, 1) = (leaf.icov_(1, 1) - sy * my) / n_minus_one;
    leaf.icov_(2, 1) = leaf.icov_(1, 2) = (leaf.icov_(1, 2) - sy * mz) / n_minus_one;
    leaf.icov_(2, 2) = (leaf.icov_(2, 2) - sz * mz) / n_minus_one;

    // Compute the inverse covariance matrix
    eigensolver.compute(leaf.icov_);
    
    Eigen::Matrix3f evals = eigensolver.eigenvalues().asDiagonal();
    Eigen::Matrix3f evecs = eigensolver.eigenvectors();

    // This ensures all eigen values are non-negative and the greatest one is positive
    if (evals(0, 0) < 0 || evals(1, 1) < 0 || evals(2, 2) <= 0) {
        leaf.centroid_[0] = std::numeric_limits<typename std::remove_reference<decltype(leaf.centroid_(0))>::type>::infinity();

        return;
    }

    // This ensures all eigen values are positive
    double min_cov_eval = min_cov_eval_mult_ * evals(2, 2);

    if (evals(0, 0) < min_cov_eval) {
        evals(0, 0) = min_cov_eval;

        if (evals(1, 1) < min_cov_eval) {
            evals(1, 1) = min_cov_eval;
        }
    }

    // Because evals is a diagonal matrix, to compute its inverse, just invert the main diagonal
    // By this step, all eigen values are positive, so inverting them should be OK
    evals(0, 0) = 1.0 / evals(0, 0);
    evals(1, 1) = 1.0 / evals(1, 1);
    evals(2, 2) = 1.0 / evals(2, 2);

    // Because the Eigen matrix are orthogonal, the its inverse can easily computed by transpose matrix
    // The inverse matrix of cov is V * D * V^T
    leaf.icov_ = evecs * evals * evecs.transpose();

    if (leaf.icov_.maxCoeff() == std::numeric_limits<float>::infinity() ||
        leaf.icov_.minCoeff() == -std::numeric_limits<float>::infinity()) {
        leaf.centroid_[0] = std::numeric_limits<typename std::remove_reference<decltype(leaf.centroid_(0))>::type>::infinity();

        return;
    }

    return;
}

template <typename PointT>
void VoxelGridBuilder<PointT>::build(const std::string & pcd_path, const std::string & output_path)
{
    std::vector<std::string> pcd_list = discoverPCDs(pcd_path);

    if (pcd_list.empty()) {
        fprintf(stderr, "Error: no PCD file was found in %s. Abort!\n", pcd_path.c_str());
        exit(EXIT_FAILURE);
    }

    fs::path out_dir(output_path);

    if (!fs::exists(out_dir)) {
        fprintf(stderr, "The directory %s does not exist! Creating one...\n", out_dir.c_str());
        fs::create_directories(out_dir);
        fprintf(stderr, "Done!\n");
    }

    for (auto & pcd_name : pcd_list) {
        fs::path full_pcd_name(pcd_name);
        // Get the file name without extension
        fs::path ndt_name(full_pcd_name.stem().string() + ".ndat");  
        fs::path ndt_path = out_dir / ndt_name;
        std::ofstream ndt_ostream(ndt_path.string(), std::ios::binary);
        PclCloudPtr new_cloud(new PclCloudType);

        // Load a PCD file
        if (pcl::io::loadPCDFile(full_pcd_name.string(), *new_cloud)) {
            fprintf(stderr, "Error: Could not load a PCD file from %s. Skip!\n", 
                    full_pcd_name.c_str());
            continue;
        }

        // Build NDT structures and write to files
        applyFilter(new_cloud, ndt_ostream);
        
        // Close the file
        ndt_ostream.close();
    }
}

template class VoxelGridBuilder<pcl::PointXYZ>;
template class VoxelGridBuilder<pcl::PointXYZI>;

}