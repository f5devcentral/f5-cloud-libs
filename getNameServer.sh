# Generated from v2.9.0

INTERFACE=$1
INTERFACE_MAC=`ifconfig ${INTERFACE} | egrep HWaddr | awk '{print tolower($5)}'`
VPC_CIDR_BLOCK=`curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${INTERFACE_MAC}/vpc-ipv4-cidr-block`
VPC_NET=${VPC_CIDR_BLOCK%/*}
NAME_SERVER=`echo ${VPC_NET} | awk -F. '{ printf "%d.%d.%d.%d", $1, $2, $3, $4+2 }'`
echo $NAME_SERVER
