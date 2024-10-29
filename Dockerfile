# args declared before first "FROM" can be accessed in a stage when mentioned
ARG USERNAME="seymour"
ARG HOME_DIR="/home/${USERNAME}"
ARG WORKSPACE="${HOME_DIR}/workspace"
ARG DDS_CONFIG_DIR="/opt/dds/config"
ARG INSTALL_DIR="/opt/deploy"

# -------------
# create base stage without ros build tools for deployment
FROM docker.io/library/ubuntu:jammy AS base-stage

ARG DEBIAN_FRONTEND="noninteractive"
ARG RUN_AS_UID=1000
ARG RUN_AS_GID=1000
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV ROS_DISTRO="humble"

# RMW_IMPLEMENTATION -> "rmw_cyclonedds_cpp" | "rmw_fastrtps_cpp"
ENV RMW_IMPLEMENTATION="rmw_fastrtps_cpp"

# mention global args we want to use in this stage
ARG USERNAME
ARG HOME_DIR
ARG WORKSPACE
ARG DDS_CONFIG_DIR

ENV CYCLONEDDS_URI="${DDS_CONFIG_DIR}/cyclonedds.xml"
ENV FASTRTPS_DEFAULT_PROFILES_FILE="${DDS_CONFIG_DIR}/fastrtps.xml"

# setup utc timeszone & install base ubuntu packages
RUN echo 'Etc/UTC' > /etc/timezone  \
  && ln -s /usr/share/zoneinfo/Etc/UTC /etc/localtime \
  && apt-get update && apt-get install -q -y --no-install-recommends \
    bash-completion \
    dirmngr \
    gnupg2 \
    python-is-python3 \
    python3-pip \
    sudo \
    tzdata \
  && echo "deb http://packages.ros.org/ros2/ubuntu jammy main" \
    > /etc/apt/sources.list.d/ros2-latest.list \
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654 \
  && apt-get update && apt-get install -q -y --no-install-recommends \
    python3-rosdep \
    ros-${ROS_DISTRO}-class-loader \
    ros-${ROS_DISTRO}-common-interfaces \
    ros-${ROS_DISTRO}-launch \
    ros-${ROS_DISTRO}-launch-ros \
    ros-${ROS_DISTRO}-launch-xml \
    ros-${ROS_DISTRO}-launch-yaml \
    ros-${ROS_DISTRO}-pluginlib \
    ros-${ROS_DISTRO}-rcl-lifecycle \
    ros-${ROS_DISTRO}-rclcpp \
    ros-${ROS_DISTRO}-rclcpp-action \
    ros-${ROS_DISTRO}-rclcpp-lifecycle \
    ros-${ROS_DISTRO}-rclpy \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    ros-${ROS_DISTRO}-rmw-fastrtps-cpp \
    ros-${ROS_DISTRO}-rosidl-default-generators \
    ros-${ROS_DISTRO}-rosidl-default-runtime \
    ros-${ROS_DISTRO}-ros-environment \
    ros-${ROS_DISTRO}-ros2launch \
    ros-${ROS_DISTRO}-ros2cli-common-extensions \
  && rm -rf /var/lib/apt/lists/*

# create non-root user with given username
# and allow sudo without password
# and setup default users .bashrc
RUN groupadd --gid $RUN_AS_GID ${USERNAME} \
  && useradd -rm \
    -d ${HOME_DIR} \
    -s /bin/bash \
    --gid ${RUN_AS_GID} \
    --uid ${RUN_AS_UID} \
    -m ${USERNAME} \
  && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
  && chmod 0440 /etc/sudoers.d/${USERNAME} \
  && echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ${HOME_DIR}/.bashrc \
  && echo "source /etc/profile.d/bash_completion.sh" >> ${HOME_DIR}/.bashrc \
  && chown -R ${USERNAME}: ${HOME_DIR}

# create workspace and source dir
RUN mkdir -p ${WORKSPACE} \
  && chown -R ${USERNAME}: ${HOME_DIR}
WORKDIR ${WORKSPACE}


# copy code into workspace and set ownership to user
ADD --chown=${USERNAME}:${USERNAME} ./src ${WORKSPACE}/src


# -------------
# build stage installs build tools and builds system packages
FROM base-stage AS build-stage

ARG DEBIAN_FRONTEND="noninteractive"

# mention global args we want to use in this stage
ARG USERNAME
ARG HOME_DIR
ARG WORKSPACE

# install build tools
# leave /var/lib/apt/lists for rosdep below
RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential \
    git \
    python3-colcon-common-extensions \
    python3-colcon-mixin \
    python3-vcstool \
  && rm -rf /var/lib/apt/lists/*

# setup colcon mixin and metadata
RUN colcon mixin add default \
    https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml && \
  colcon mixin update && \
  colcon metadata add default \
    https://raw.githubusercontent.com/colcon/colcon-metadata-repository/master/index.yaml && \
  colcon metadata update

# create workspace and source dir
RUN mkdir -p ${WORKSPACE} \
  && chown -R ${USERNAME}: ${HOME_DIR}
WORKDIR ${WORKSPACE}

# copy code into workspace and set ownership to user
ADD --chown=${USERNAME}:${USERNAME} ./src ${WORKSPACE}/src

# install deps and build as non-root user
USER ${USERNAME}
RUN /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash \
  && sudo apt-get update \
  && sudo rosdep init \
  && rosdep update --rosdistro ${ROS_DISTRO} \
  && rosdep install -y -r -i --from-paths ${WORKSPACE}/src \
  && colcon build \
  && sudo rm -rf /var/lib/apt/lists/*"


# -------------
# last stage will copy installed code without all the build tools
FROM base-stage

# label with source repo
LABEL org.opencontainers.image.source \
  https://github.com/freshrobotics/seymour-deploy

ARG DEBIAN_FRONTEND="noninteractive"

# mention global args we want to use in this stage
ARG USERNAME
ARG HOME_DIR
ARG WORKSPACE
ARG DDS_CONFIG_DIR
ARG INSTALL_DIR

RUN mkdir -p ${INSTALL_DIR} \
  && echo "source ${INSTALL_DIR}/setup.bash" >> ${HOME_DIR}/.bashrc

WORKDIR ${INSTALL_DIR}

# copy the installed ros code from the build stage
COPY --from=build-stage ${WORKSPACE}/install ${INSTALL_DIR}

# setup dds config
ADD ./dds_config ${DDS_CONFIG_DIR}

# switch to non-root user
USER ${USERNAME}

# install ROS package runtime dependencies
# - delete the COLCON_IGNORE file from the install dir
#   otherwise rosdep (below) wont find any dependencies :P
# - update apt repo list before & rm -rf after
RUN /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash \
  && sudo rm ${INSTALL_DIR}/COLCON_IGNORE \
  && sudo apt-get update \
  && sudo rosdep init \
  && rosdep update --rosdistro ${ROS_DISTRO} \
  && rosdep install -y -r -i --from-paths ${INSTALL_DIR} -t exec \
  && sudo rm -rf /var/lib/apt/lists/*"

WORKDIR ${HOME_DIR}

# by default hold container open in background
CMD ["tail", "-f", "/dev/null"]
