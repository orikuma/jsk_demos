cmake_minimum_required(VERSION 2.8.3)
project(drc_com_common)

find_package(catkin REQUIRED COMPONENTS
  cmake_modules message_generation std_msgs std_srvs sensor_msgs
  jsk_network_tools
  dynamic_reconfigure
  roseus)

add_message_files(FILES
  FC2OCSLarge.msg FC2OCSSmall.msg OCS2FCSmall.msg
  FC2OCSBasicInfoSmall.msg
  HumanoidJointAngles.msg)
generate_messages(DEPENDENCIES sensor_msgs)
generate_dynamic_reconfigure_options(
  cfg/DRCParameters.cfg
  )

catkin_package()

install(DIRECTORY scripts launch config
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
  USE_SOURCE_PERMISSIONS)
