{
            "Comment": "CREATE/DELETE/UPSERT CNAME  record for ${BASE_DOMAIN} ",
            "Changes": [{
            "Action": "UPSERT",
            "ResourceRecordSet": {
               "Name": "*.${BASE_DOMAIN}",
               "Type": "A",
               "TTL": 30,
               "ResourceRecords": [{ "Value": "${LB_IP}"}]
            }
         }
      ]
}
