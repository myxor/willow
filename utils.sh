#!/bin/bash
set -e # bail on error

export PLATFORM="esp32s3" # Current general family
export FLASH_BAUD=1843200 # Optimistic but seems to work for me for now
export CONSOLE_BAUD=115200 # Subject to change

export SALLOW_PATH="$PWD"
export ADF_PATH="$SALLOW_PATH/deps/esp-adf"

check_port() {
if [ ! $PORT ]; then
    echo "You need to define the PORT environment variable to do serial stuff - exiting"
    exit 1
fi

if [ ! -c $PORT ]; then
    echo "Cannot find configured port $PORT - exiting"
    exit 1
fi
}

print_monitor_help() {
echo "
You can exit the serial monitor with CTRL + A and then k
"
}

mac_esptool() {
    if [ ! -d venv ]; then
        echo "Creating venv for mac"
        python3 -m venv venv
        source venv/bin/activate
        echo "Installing esptool..."
        pip install esptool
    else
        echo "Using venv for mac"
        source venv/bin/activate
    fi
}

check_screen() {
    if ! command -v screen &> /dev/null
    then
        echo "GNU Screen could not be found in path - you need to install it"
        exit 1
    fi
}

do_screen() {
    screen "$PORT" "$CONSOLE_BAUD"
}

check_docker(){
    if [ ! -f /.dockerenv ]; then
        echo "You need to run this command inside of the docker image";
        exit 1
    fi
}

check_deps() {
    if [ ! -d deps/esp-adf ]; then
        echo "You need to run install first"
        exit 1
    fi
}

# Some of this may seem redundant but for build, clean, etc we'll probably need to do our own stuff later
case $1 in

config)
    check_docker
    check_deps
    idf.py menuconfig
;;

clean)
    check_docker
    check_deps
    idf.py clean
;;

fullclean)
    check_docker
    check_deps
    idf.py fullclean
;;

build)
    check_docker
    check_deps
    idf.py build
;;

build-docker)
    docker build -t sallow:latest .
;;

docker)
    check_port
    docker run --rm -it -v "$PWD":/sallow -v /dev:/dev --privileged -e PORT -e TERM sallow:latest /bin/bash
;;

# Needs to be updated if we change the partitions
mac-flash)
    check_port
    check_screen
    mac_esptool
    cd build
    python3 -m esptool --chip "$PLATFORM" -p "$PORT" -b "$FLASH_BAUD" --before=default_reset --after=hard_reset write_flash \
        --flash_mode dio --flash_freq 80m --flash_size 16MB 0x0 bootloader/bootloader.bin 0x10000 sallow.bin 0x8000 \
        partition_table/partition-table.bin 0x390000 audio.bin 0x210000 model.bin
    print_monitor_help
    do_screen
;;

mac-flash-app)
    check_port
    check_screen
    mac_esptool
    cd build
    python3 -m esptool --chip "$PLATFORM" -p "$PORT" -b "$FLASH_BAUD" --before=default_reset --after=hard_reset write_flash \
        --flash_mode dio --flash_freq 80m --flash_size 16MB 0x10000 sallow.bin
    print_monitor_help
    do_screen
;;

flash)
    check_port
    check_screen
    check_docker
    check_deps
    print_monitor_help
    idf.py -p "$PORT" -b "$FLASH_BAUD" flash
    do_screen
;;

monitor)
    check_port
    check_screen
    print_monitor_help
    do_screen
;;

destroy)
    echo "YOU ARE ABOUT TO REMOVE THIS ENTIRE ENVIRONMENT AND RESET THE REPO. HIT ENTER TO CONFIRM."
    read
    echo "SERIOUSLY - YOU WILL LOSE WORK AND I WILL NOT STOP YOU IF YOU HIT ENTER AGAIN!"
    read
    echo "LAST CHANCE!"
    read
    #git reset --hard
    #git clean -fdx
    rm -rf build/*
    rm -rf deps target venv
    echo "Not a trace left. You will have to run setup again."
;;

install|setup)
    check_docker
    if [ -d deps ]; then
        echo "You already have a deps directory - exiting"
        exit 1
    fi
    mkdir -p deps
    cd deps
    # Setup ADF
    git clone -b "$ADF_VER" https://github.com/espressif/esp-adf.git
    cd $ADF_PATH
    git submodule update --init components/esp-adf-libs

    cd $SALLOW_PATH
    cp sdkconfig.sallow sdkconfig

    echo "You can now run ./utils.sh config and navigate to Sallow Configuration for your environment"
;;

*)
    check_docker
    echo "Passing args directly to idf.py"
    idf.py "$@"
;;

esac
