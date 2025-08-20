cmake_minimum_required(VERSION 3.5)
project(autoware_e2e_map_update)

find_package(autoware_cmake REQUIRED)
autoware_package()

install(PROGRAMS
  scripts/mapfourmer.sh
  scripts/map_update.sh
  scripts/install.sh
  DESTINATION lib/${PROJECT_NAME}
)

# ament_auto_package(INSTALL_TO_SHARE launch config)
ament_auto_package()
