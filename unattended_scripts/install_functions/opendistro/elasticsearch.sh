# Copyright (C) 2015-2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

installElasticsearch() {

    logger "Starting Open Distro for Elasticsearch installation."

    if [ ${sys_type} == "yum" ]; then
        eval "yum install opendistroforelasticsearch-${opendistro_version}-${opendistro_revision} -y ${debug}"
    elif [ ${sys_type} == "zypper" ]; then
        eval "zypper -n install opendistroforelasticsearch=${opendistro_version}-${opendistro_revision} ${debug}"
    elif [ ${sys_type} == "apt-get" ]; then
        eval "apt install elasticsearch-oss opendistroforelasticsearch -y ${debug}"
    fi

    if [  "$?" != 0  ]; then
        logger -e "Elasticsearch installation failed."
        rollBack
        exit 1;  
    else
        elasticsearchinstalled="1"
         logger "Open Distro for Elasticsearch installation finished."
    fi
}

copyCertificatesElasticsearch() {
    
    if [ ${#elasticsearch_node_names[@]} -eq 1 ]; then
        name=${einame}
    else
        name=${elasticsearch_node_names[pos]}
    fi

    eval "cp ${base_path}/certs/${name}.pem /etc/elasticsearch/certs/elasticsearch.pem ${debug}"
    eval "cp ${base_path}/certs/${name}-key.pem /etc/elasticsearch/certs/elasticsearch-key.pem ${debug}"
    eval "cp ${base_path}/certs/root-ca.pem /etc/elasticsearch/certs/ ${debug}"
    eval "cp ${base_path}/certs/admin.pem /etc/elasticsearch/certs/ ${debug}"
    eval "cp ${base_path}/certs/admin-key.pem /etc/elasticsearch/certs/ ${debug}"
}

applyLog4j2Mitigation(){

    eval "curl -so /tmp/apache-log4j-2.17.0-bin.tar.gz https://dlcdn.apache.org/logging/log4j/2.17.0/apache-log4j-2.17.0-bin.tar.gz ${debug}"
    eval "tar -xf /tmp/apache-log4j-2.17.0-bin.tar.gz -C /tmp/"

    eval "cp /tmp/apache-log4j-2.17.0-bin/log4j-api-2.17.0.jar /usr/share/elasticsearch/lib/  ${debug}"
    eval "cp /tmp/apache-log4j-2.17.0-bin/log4j-core-2.17.0.jar /usr/share/elasticsearch/lib/ ${debug}"
    eval "cp /tmp/apache-log4j-2.17.0-bin/log4j-slf4j-impl-2.17.0.jar /usr/share/elasticsearch/plugins/opendistro_security/ ${debug}"
    eval "cp /tmp/apache-log4j-2.17.0-bin/log4j-api-2.17.0.jar /usr/share/elasticsearch/performance-analyzer-rca/lib/ ${debug}"
    eval "cp /tmp/apache-log4j-2.17.0-bin/log4j-core-2.17.0.jar /usr/share/elasticsearch/performance-analyzer-rca/lib/ ${debug}"

    eval "rm -f /usr/share/elasticsearch/lib//log4j-api-2.11.1.jar ${debug}"
    eval "rm -f /usr/share/elasticsearch/lib/log4j-core-2.11.1.jar ${debug}"
    eval "rm -f /usr/share/elasticsearch/plugins/opendistro_security/log4j-slf4j-impl-2.11.1.jar ${debug}"
    eval "rm -f /usr/share/elasticsearch/performance-analyzer-rca/lib/log4j-api-2.13.0.jar ${debug}"
    eval "rm -f /usr/share/elasticsearch/performance-analyzer-rca/lib/log4j-core-2.13.0.jar ${debug}"

    eval "rm -rf /tmp/apache-log4j-2.17.0-bin ${debug}"
    eval "rm -f /tmp/apache-log4j-2.17.0-bin.tar.gz ${debug}"

}

configureElasticsearchAIO() {

    eval "getConfig elasticsearch/elasticsearch_all_in_one.yml /etc/elasticsearch/elasticsearch.yml ${debug}"
    eval "getConfig elasticsearch/roles/roles.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles.yml ${debug}"
    eval "getConfig elasticsearch/roles/roles_mapping.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles_mapping.yml ${debug}"
    eval "getConfig elasticsearch/roles/internal_users.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/internal_users.yml ${debug}"
    
    eval "rm /etc/elasticsearch/esnode-key.pem /etc/elasticsearch/esnode.pem /etc/elasticsearch/kirk-key.pem /etc/elasticsearch/kirk.pem /etc/elasticsearch/root-ca.pem -f ${debug}"
    eval "export JAVA_HOME=/usr/share/elasticsearch/jdk/"

    eval "mkdir /etc/elasticsearch/certs/ ${debug}"
    eval "cp ${base_path}/certs/elasticsearch* /etc/elasticsearch/certs/ ${debug}"
    eval "cp ${base_path}/certs/root-ca.pem /etc/elasticsearch/certs/ ${debug}"
    eval "cp ${base_path}/certs/admin* /etc/elasticsearch/certs/ ${debug}"
    
    # Configure JVM options for Elasticsearch
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    ram=$(( ${ram_gb} / 2 ))

    if [ ${ram} -eq "0" ]; then
        ram=1;
    fi    
    eval "sed -i "s/-Xms1g/-Xms${ram}g/" /etc/elasticsearch/jvm.options ${debug}"
    eval "sed -i "s/-Xmx1g/-Xmx${ram}g/" /etc/elasticsearch/jvm.options ${debug}"

    eval "/usr/share/elasticsearch/bin/elasticsearch-plugin remove opendistro-performance-analyzer ${debug}"

    applyLog4j2Mitigation
    logger "Elasticsearch post-install configuration finished."

}

configureElasticsearch() {
    logger "Configuring Elasticsearch."

    eval "getConfig elasticsearch/elasticsearch_unattended_distributed.yml /etc/elasticsearch/elasticsearch.yml ${debug}"
    eval "getConfig elasticsearch/roles/roles.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles.yml ${debug}"
    eval "getConfig elasticsearch/roles/roles_mapping.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles_mapping.yml ${debug}"
    eval "getConfig elasticsearch/roles/internal_users.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/internal_users.yml ${debug}"
    
    if [ ${#elasticsearch_node_names[@]} -eq 1 ]; then
        pos=0
        echo "node.name: ${einame}" >> /etc/elasticsearch/elasticsearch.yml
        echo "network.host: ${elasticsearch_node_ips[0]}" >> /etc/elasticsearch/elasticsearch.yml
        echo "cluster.initial_master_nodes: ${einame}" >> /etc/elasticsearch/elasticsearch.yml

        echo "opendistro_security.nodes_dn:" >> /etc/elasticsearch/elasticsearch.yml
        echo '        - CN='${einame}',OU=Docu,O=Wazuh,L=California,C=US' >> /etc/elasticsearch/elasticsearch.yml
    else
        echo "node.name: ${einame}" >> /etc/elasticsearch/elasticsearch.yml
        echo "cluster.initial_master_nodes:" >> /etc/elasticsearch/elasticsearch.yml
        for i in ${elasticsearch_node_names[@]}; do
            echo '        - "'${i}'"' >> /etc/elasticsearch/elasticsearch.yml
        done

        echo "discovery.seed_hosts:" >> /etc/elasticsearch/elasticsearch.yml
        for i in ${elasticsearch_node_ips[@]}; do
            echo '        - "'${i}'"' >> /etc/elasticsearch/elasticsearch.yml
        done

        for i in ${!elasticsearch_node_names[@]}; do
            if [[ "${elasticsearch_node_names[i]}" == "${einame}" ]]; then
                pos="${i}";
            fi
        done

        echo "network.host: ${elasticsearch_node_ips[pos]}" >> /etc/elasticsearch/elasticsearch.yml

        echo "opendistro_security.nodes_dn:" >> /etc/elasticsearch/elasticsearch.yml
        for i in "${elasticsearch_node_names[@]}"; do
                echo '        - CN='${i}',OU=Docu,O=Wazuh,L=California,C=US' >> /etc/elasticsearch/elasticsearch.yml
        done

    fi

    eval "rm /etc/elasticsearch/esnode-key.pem /etc/elasticsearch/esnode.pem /etc/elasticsearch/kirk-key.pem /etc/elasticsearch/kirk.pem /etc/elasticsearch/root-ca.pem -f ${debug}"
    eval "mkdir /etc/elasticsearch/certs ${debug}"

    # Configure JVM options for Elasticsearch
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    ram=$(( ${ram_gb} / 2 ))

    if [ ${ram} -eq "0" ]; then
        ram=1;
    fi
    eval "sed -i "s/-Xms1g/-Xms${ram}g/" /etc/elasticsearch/jvm.options ${debug}"
    eval "sed -i "s/-Xmx1g/-Xmx${ram}g/" /etc/elasticsearch/jvm.options ${debug}"

    applyLog4j2Mitigation

    jv=$(java -version 2>&1 | grep -o -m1 '1.8.0' )
    if [ "$jv" == "1.8.0" ]; then
        echo "root hard nproc 4096" >> /etc/security/limits.conf
        echo "root soft nproc 4096" >> /etc/security/limits.conf
        echo "elasticsearch hard nproc 4096" >> /etc/security/limits.conf
        echo "elasticsearch soft nproc 4096" >> /etc/security/limits.conf
        echo "bootstrap.system_call_filter: false" >> /etc/elasticsearch/elasticsearch.yml
    fi

    copyCertificatesElasticsearch

    eval "rm /etc/elasticsearch/certs/client-certificates.readme /etc/elasticsearch/certs/elasticsearch_elasticsearch_config_snippet.yml -f ${debug}"
    eval "/usr/share/elasticsearch/bin/elasticsearch-plugin remove opendistro-performance-analyzer ${debug}"

}

initializeElasticsearch() {


    logger "Starting Elasticsearch."
    until $(curl -XGET https://${elasticsearch_node_ips[pos]}:9200/ -uadmin:admin -k --max-time 120 --silent --output /dev/null); do
        sleep 10
    done

    if [ ${#elasticsearch_node_names[@]} -eq 1 ]; then
        eval "export JAVA_HOME=/usr/share/elasticsearch/jdk/"
        eval "/usr/share/elasticsearch/plugins/opendistro_security/tools/securityadmin.sh -cd /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/ -icl -nhnv -cacert /etc/elasticsearch/certs/root-ca.pem -cert /etc/elasticsearch/certs/admin.pem -key /etc/elasticsearch/certs/admin-key.pem -h ${elasticsearch_node_ips[pos]} ${debug}"
    fi

    logger "Elasticsearch started."
}

startElasticsearchCluster() {

    eval "elasticsearch_cluster_ip=( $(cat /etc/elasticsearch/elasticsearch.yml | grep network.host | sed 's/network.host:\s//') )"
    eval "export JAVA_HOME=/usr/share/elasticsearch/jdk/"
    eval "/usr/share/elasticsearch/plugins/opendistro_security/tools/securityadmin.sh -cd /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/ -icl -nhnv -cacert /etc/elasticsearch/certs/root-ca.pem -cert /etc/elasticsearch/certs/admin.pem -key /etc/elasticsearch/certs/admin-key.pem -h ${elasticsearch_cluster_ip}"
    eval "curl ${filebeat_wazuh_template} | curl -X PUT 'https://${elasticsearch_node_ips[pos]}:9200/_template/wazuh' -H 'Content-Type: application/json' -d @- -uadmin:admin -k ${debug}"

}
