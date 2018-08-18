#!/bin/bash
# Generated from v2.9.0
set -e
date
. /config/cloud/aws/onboard_config_vars
BIGIP_ASG_NAME=`f5-rest-node /config/cloud/aws/node_modules/f5-cloud-libs/node_modules/f5-cloud-libs-aws/scripts/getAutoscaleGroupName.js` 
tmsh modify sys autoscale-group autoscale-group-id ${BIGIP_ASG_NAME} 
tmsh create sys icall script uploadMetrics definition { exec /config/cloud/aws/node_modules/f5-cloud-libs/node_modules/f5-cloud-libs-aws/scripts/reportMetrics.sh }
tmsh create sys icall handler periodic /Common/metricUploadHandler { first-occurrence now interval 60 script /Common/uploadMetrics }
(crontab -l 2>/dev/null; echo '*/2 * * * * /config/cloud/aws/run_autoscale_update.sh') | crontab -
tmsh save /sys config
echo 'Attempting to Join or Initiate LTM Autoscale Cluster' 
f5-rest-node /config/cloud/aws/node_modules/f5-cloud-libs/scripts/autoscale.js --cloud aws --provider-options s3Bucket:${s3Bucket},sqsUrl:${sqsUrl},mgmtPort:${managementGuiPort} --host localhost --port ${managementGuiPort} --user cluster-admin --password-url file:///config/cloud/aws/.adminPassword --password-encrypted --device-group autoscale-group --block-sync -c join --log-level debug --output /var/log/cloud/aws/aws-autoscale.log
if [ -f /config/cloud/master ]; then 
  if `jq '.ucsLoaded' < /config/cloud/master`; then 
    echo "UCS backup loaded from backup folder in S3 bucket ${s3Bucket}."
  else
    echo 'SELF-SELECTED as LTM Master ... Initiated LTM Autoscale Cluster ... Loading default config'
    tmsh load sys application template /config/cloud/f5.http.v1.2.0rc7.tmpl
    tmsh load sys application template /config/cloud/aws/f5.service_discovery.tmpl
    ### START CUSTOM CONFIGURTION: 
    if [[ "${appCertificateS3Arn}" != "default" ]]; then
        f5-rest-node /config/cloud/aws/node_modules/f5-cloud-libs/node_modules/f5-cloud-libs-aws/scripts/getCertFromS3.js ${appCertificateS3Arn}
        tmsh install sys crypto pkcs12 site.example.com from-local-file /config/ssl/ssl.key/${appCertificateS3Arn##*/}
        tmsh create ltm profile client-ssl example-clientssl-profile cert site.example.com.crt key site.example.com.key
    else
        tmsh create ltm profile client-ssl example-clientssl-profile cert default.crt key default.key
    fi
    tmsh create ltm pool ${poolName1} { monitor http }
    tmsh create ltm pool ${poolName2} { monitor http }
    tmsh create ltm policy uri-routing-policy controls add { forwarding } requires add { http } strategy first-match legacy 
    tmsh modify ltm policy uri-routing-policy rules add { uri_1 { conditions add { 0 { http-uri path starts-with values { /static } } } actions add { 0 { forward select pool ${poolName1} } } ordinal 1 } } 
    tmsh modify ltm policy uri-routing-policy rules add { uri_2 { conditions add { 0 { http-uri path starts-with values { /api } } } actions add { 0 { forward select pool ${poolName2} } } ordinal 2 } } 
    tmsh create sys application service ${appName} { device-group autoscale-group template f5.http.v1.2.0rc7 lists add { local_traffic__policies { value { /Common/uri-routing-policy } } } tables add { pool__hosts { column-names { name } rows { { row { ${appName} } } } }  pool__members { column-names { addr port connection_limit } rows {{ row { ${appName} ${applicationPort} 0 }}}}} variables add { pool__pool_to_use { value /Common/${poolName1} } pool__addr { value 0.0.0.0 } pool__mask { value 0.0.0.0 } pool__port { value ${virtualServicePort} } net__vlan_mode { value all } monitor__http_version { value http11 } ssl__client_ssl_profile { value /Common/example-clientssl-profile } ssl__mode { value client_ssl } ssl_encryption_questions__advanced { value yes } pool__port_secure { value 443 } pool__redirect_to_https { value yes } pool__redirect_port { value 80 }   }}
    tmsh create sys application service ${poolName1}_sd { template f5.service_discovery variables add { cloud__aws_use_role { value no } cloud__cloud_provider { value aws } cloud__aws_region { value ${region} } pool__interval { value 15 } pool__lb_method_choice { value least-connections-member } pool__member_conn_limit { value 0 } pool__pool_to_use { value /Common/${poolName1} } pool__member_port { value ${applicationPort} } pool__public_private { value private } pool__tag_key { value ${applicationPoolTagKey} } pool__tag_value { value ${application1PoolTagValue} } }}
    tmsh create sys application service ${poolName2}_sd { template f5.service_discovery variables add { cloud__aws_use_role { value no } cloud__cloud_provider { value aws } cloud__aws_region { value ${region} } pool__interval { value 15 } pool__lb_method_choice { value least-connections-member } pool__member_conn_limit { value 0 } pool__pool_to_use { value /Common/${poolName2} } pool__member_port { value ${applicationPort} } pool__public_private { value private } pool__tag_key { value ${applicationPoolTagKey} } pool__tag_value { value ${application2PoolTagValue} } }}
    tmsh modify sys application service ${appName}.app/${appName} { variables add { client__standard_caching_without_wa { value \"/#do_not_use#\" } } } 
    tmsh modify sys application service ${appName}.app/${appName} execute-action definition 
    tmsh modify ltm virtual /Common/${appName}.app/${appName}_vs profiles add { websocket }
    # CREATE QUICKSTART USER
    quickstartPassword=$(cat /shared/vadc/aws/iid-document | jq -r .instanceId)
    tmsh create auth user quickstart password ${quickstartPassword} shell bash partition-access replace-all-with { all-partitions { role admin } }
    ### END CUSTOM CONFIGURATION
    tmsh save /sys config
    f5-rest-node /config/cloud/aws/node_modules/f5-cloud-libs/scripts/autoscale.js --cloud aws --provider-options s3Bucket:${s3Bucket},sqsUrl:${sqsUrl},mgmtPort:${managementGuiPort}      --host localhost --port ${managementGuiPort} --user cluster-admin --password-url file:///config/cloud/aws/.adminPassword --password-encrypted --log-level debug -c unblock-sync
  fi
fi
date
echo 'custom-config.sh complete'
