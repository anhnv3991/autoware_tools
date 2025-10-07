import os
import argparse
import yaml
import open3d as o3d
import numpy as np

from rclpy.node import Node

class PCDChecker(Node):
    def __init__(self):
        self.dir_path = ""
    
    def verify(self, dir_path: str):
        print("Checking the existence of the input directory...", end = "")
        if os.path.exists(dir_path):
            self.__pass()
        else:
            self.__fail(f"The PCD directory does not exist at {dir_path}")

        self.dir_path = dir_path

        self.__setup_paths()
        self.__check_pcd_01_01()
        self.__check_pcd_01_02()
        self.__check_pcd_01_03()
        self.__check_pcd_01_04()
        self.__check_pcd_01_05()
        self.__check_pcd_02_01()
        self.__check_pcd_03_01()
        self.__check_pcd_03_02_01()
        self.__check_pcd_03_02_02()
        self.__check_pcd_03_02_03()
        self.__check_pcd_03_02_04()
        self.__check_pcd_03_02_05()
        
        print("Finished!")


    def __check_pcd_01_01(self):
        pass

    def __check_pcd_01_02(self):
        print("Checking pcd-01-02: verify the map segmentation...", end = "")
        err_msg = ""
        
        with open(self.pcd_meta_path) as f:
            data = yaml.safe_load(f)

        for key, value in data.items():
            if key == "x_resolution" or key == "y_resolution":
                continue
            pcd_path = os.path.join(self.pcd_path, key)
            if not self.__segment_checker(pcd_path, value):
                err_msg += f"File key contains out-of-bound points\n"

        if err_msg == "":
            self.__pass()
        else:
            self.__fail(err_msg)    

    def __check_pcd_01_03(self):
        print("Checking pcd-01-03: verify the file structures...", end = "")
        err_msg = ""
        if not os.path.exists(self.lanelet2_map_path):
            err_msg += f"The lanelet2_map.osm does not exist at {self.lanelet2_map_path}\n"

        if not os.path.exists(self.pcd_path):
            err_msg += f"The pointcloud_map.pcd does not exist at {self.pcd_path}\n"

        if not os.path.exists(self.map_proj_info_path):
            err_msg += f"The map_projector_info.yaml does not exist at {self.map_proj_info_path}\n"
        
        if not os.path.exists(self.pcd_meta_path):
            err_msg += f"The pointcloud_map_metadata.yaml does not exist at {self.pcd_meta_path}\n"
        
        if err_msg == "":
            self.__pass()
        else:
            self.__fail(err_msg)

    def __check_pcd_01_04(self):
        print("Checking pcd-01-04: verify the TM Coordinate System in map_projector_info.yaml...")
        err_msg = ""
        with open(self.map_proj_info_path) as f:
            data = yaml.safe_load(f)

        if not "projector_type" in data:
            err_msg += f"projector_type is not in the map_projector_info.yaml\n"
    
        if not "vertical_datum" in data:
            err_msg += f"vertical_datum is not in the map_projector_info.yaml\n"
        
        if not "map_origin" in data:
            err_msg += f"map_origin is not in the map_projector_info.yaml\n"

        if not "latitude" in data["map_origin"]:
            err_msg += f"latitude is not in the map_projector_info.yaml\n"
        
        if not "longitude" in data["map_origin"]:
            err_msg += f"longitude is not in the map_projector_info.yaml\n"
        
        if not "scale_factor" in data:
            err_msg += f"scale_factor is not in the map_projector_info.yaml\n"
        
        if err_msg == "":
            self.__pass()
        else:
            self.__fail(err_msg)


    def __check_pcd_01_05(self):
        print("Checking pcd-01-05: verify the file pointcloud_map_metadata.yaml...")
        err_msg = ""
        with open(self.pcd_meta_path) as f:
            data = yaml.safe_load(f)

        for key, value in data.items():
            if key != "x_resolution" and key != "y_resolution" and not key.endswith(".pcd"):
                err_msg += f"Field {key} is not valid\n" 

        if err_msg == "":
            self.__pass()
        else:
            self.__fail(err_msg)

    def __check_pcd_02_01(self):
        pass

    def __check_pcd_03_01(self):
        # Temporarily skip this because it is a little bit complicate 
        # and must be checked by C++ code
        pass

    def __check_pcd_03_02(self):
        pass

    def __check_pcd_03_02_01(self):
        pass

    def __check_pcd_03_02_02(self):
        pass

    def __check_pcd_03_02_03(self):
        pass

    def __check_pcd_03_02_04(self):
        pass

    def __check_pcd_03_02_05(self):
        pass

    def __setup_paths(self):
        self.lanelet2_map_path = os.path.join(self.dir_path, "lanelet2_map.osm")
        self.pcd_path = os.path.join(self.dir_path, "pointcloud_map.pcd")
        self.map_proj_info_path = os.path.join(self.dir_path, "map_projector_info.yaml")
        self.pcd_meta_path = os.path.join(self.dir_path, "pointcloud_map_metadata.yaml")

    def __segment_checker(self, pcd_path : str, lower_bound : list):
        pcd = o3d.io.read_point_cloud(pcd_path)
        points = np.asarray(pcd.points)
        lower_bound = np.asarray(lower_bound)
        upper_bound = lower_bound + 20

        # Check if every point is within the lower and upper bound
        check = (points >= lower_bound & points < upper_bound)

        return check.all()

    def __pass(self):
        print("\033[92mPASS\033[0m")

    def __fail(self, err_msg: str):
        print("\033[91mFAIL\033[0m")
        print(f"\tError: {err_msg}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("map_path", help = "The path to the map folder")

    args = parser.parse_args()

    print("The input map is at: {0}".format(args.map_path))

    checker = PCDChecker()

    checker.verify(args.map_path)