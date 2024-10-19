#!/usr/bin/env bash
set -eux

apt-get update
apt-get install -y debootstrap squashfs-tools

mkdir /tmp/chroot

# Install ubuntu into a chroot for us to later install our dependencies into.
debootstrap --variant=minbase noble /tmp/chroot http://archive.ubuntu.com/ubuntu
# The devices cause untar issues and we don't need them.
rm -rf /tmp/chroot/dev/*

cat <<EOF > /tmp/chroot/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu noble main
deb http://archive.ubuntu.com/ubuntu noble universe
deb http://archive.ubuntu.com/ubuntu noble multiverse
deb http://archive.ubuntu.com/ubuntu noble restricted
EOF

cat <<EOF >> /tmp/chroot/etc/openpilot-env
export DEBIAN_FRONTEND=noninteractive 
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute
export QTWEBENGINE_DISABLE_SANDBOX=1
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export PYTHONUNBUFFERED=1
EOF

cat <<EOF > /tmp/chroot/tmp/install-locales.sh
#!/usr/bin/env bash
set -eux

apt-get update
apt-get install -y --no-install-recommends locales

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
EOF
chmod +x /tmp/chroot/tmp/install-locales.sh

cat <<EOF > /tmp/chroot/tmp/install-deps.sh
#!/usr/bin/env bash
set -eux

apt-get install -y --no-install-recommends \
  sudo \
  tzdata \
  ssh \
  pulseaudio \
  xvfb \
  x11-xserver-utils \
  gnome-screenshot \
  apt-utils \
  alien \
  unzip \
  tar \
  curl \
  xz-utils \
  dbus \
  gcc-arm-none-eabi \
  tmux \
  vim \
  libx11-6 \
  python3-dev \
  python3-venv \
  wget

env
dbus-uuidgen > /etc/machine-id

. /etc/openpilot-env

cd /tmp/openpilot

./tools/ubuntu_setup.sh

mkdir -p /tmp/opencl-driver-intel
cd /tmp/opencl-driver-intel
wget https://github.com/intel/llvm/releases/download/2024-WW14/oclcpuexp-2024.17.3.0.09_rel.tar.gz
wget https://github.com/oneapi-src/oneTBB/releases/download/v2021.12.0/oneapi-tbb-2021.12.0-lin.tgz
mkdir -p /opt/intel/oclcpuexp_2024.17.3.0.09_rel
cd /opt/intel/oclcpuexp_2024.17.3.0.09_rel
tar -zxvf /tmp/opencl-driver-intel/oclcpuexp-2024.17.3.0.09_rel.tar.gz
mkdir -p /etc/OpenCL/vendors
echo /opt/intel/oclcpuexp_2024.17.3.0.09_rel/x64/libintelocl.so > /etc/OpenCL/vendors/intel_expcpu.icd
cd /opt/intel
tar -zxvf /tmp/opencl-driver-intel/oneapi-tbb-2021.12.0-lin.tgz
ln -s /opt/intel/oneapi-tbb-2021.12.0/lib/intel64/gcc4.8/libtbb.so /opt/intel/oclcpuexp_2024.17.3.0.09_rel/x64
ln -s /opt/intel/oneapi-tbb-2021.12.0/lib/intel64/gcc4.8/libtbbmalloc.so /opt/intel/oclcpuexp_2024.17.3.0.09_rel/x64
ln -s /opt/intel/oneapi-tbb-2021.12.0/lib/intel64/gcc4.8/libtbb.so.12 /opt/intel/oclcpuexp_2024.17.3.0.09_rel/x64
ln -s /opt/intel/oneapi-tbb-2021.12.0/lib/intel64/gcc4.8/libtbbmalloc.so.2 /opt/intel/oclcpuexp_2024.17.3.0.09_rel/x64
mkdir -p /etc/ld.so.conf.d 
echo /opt/intel/oclcpuexp_2024.17.3.0.09_rel/x64 > /etc/ld.so.conf.d/libintelopenclexp.conf
cd /
rm -rf /tmp/opencl-driver-intel

# Remove arm architecture toolchains that we don't want.
cd /usr/lib/gcc/arm-none-eabi/*
rm -rf arm/ thumb/nofp thumb/v6* thumb/v8* thumb/v7+fp thumb/v7-r+fp.sp

git config --global --add safe.directory /tmp/openpilot

# Cleanup tmp files we don't want to keep.
for f in /tmp/* /tmp/.*
do
  if test "\$f" = /tmp/openpilot ; then
    continue
  fi
  rm -rvf "\$f"
done

# Remove cached apt archives.
apt clean
EOF
chmod +x /tmp/chroot/tmp/install-deps.sh

cat <<EOF > /tmp/chroot/run_ci.sh
#!/usr/bin/env bash
set -eux
cd /tmp/openpilot
. /etc/openpilot-env
. ./.venv/bin/activate
bash -c "\$1"
EOF
chmod +x /tmp/chroot/run_ci.sh

cp /etc/resolv.conf /tmp/chroot/resolv.conf
mount --bind /proc /tmp/chroot/proc
mount --bind /sys /tmp/chroot/sys
mount --bind /dev /tmp/chroot/dev
mkdir /tmp/chroot/tmp/openpilot
mount --bind "$GITHUB_WORKSPACE" /tmp/chroot/tmp/openpilot
chroot /tmp/chroot bash /tmp/install-locales.sh
chroot /tmp/chroot bash /tmp/install-deps.sh
umount /tmp/chroot/tmp/openpilot
umount /tmp/chroot/proc
umount /tmp/chroot/sys
umount /tmp/chroot/dev
# We need to move the venv out so it gets saved in the squashfs.
mv "$GITHUB_WORKSPACE/.venv" /tmp/chroot/tmp/.venv
# A squashfs is faster than docker and we don't need to decompress unused files.
cd /tmp/chroot
mksquashfs . /tmp/chroot.squashfs -b 512k -comp zstd -Xcompression-level 15
cd /
rm -rf /tmp/chroot