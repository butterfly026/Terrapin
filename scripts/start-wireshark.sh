#!/bin/bash
wireshark -i lo \
  -k \
  -d tcp.port==22sh \
  -d tcp.port==21,ssh \
  -Y ssh
