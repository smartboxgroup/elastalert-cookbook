# Runs monitoring checks on elasticsearch data using elastalert

# elastalert docker image
docker_image "#{node['docker']['registry']}/#{node['docker']['elastalert']['image']}" do
  tag node['docker']['elastalert']['tag']
  read_timeout 3600
  action :pull_if_missing
end

directory node['elastalert']['log_dir'] do
  recursive true
end

%w{rules config}.each do |dir|
  directory "#{node['elastalert']['conf_dir']}/#{dir}" do
    recursive true
  end
end

# Find Elastic Search node to query
if Chef::Config[:solo]
  Chef::Log.warn('Skipping node search when using chef-solo')
else
  node.default['elastalert']['es_host'] = search(:node, node['elastalert']['es_node_search_query']).first.ipaddress
end

%w{elastalert_config.yaml elastalert_supervisord.conf}.each do |config_file|
  template "#{node['elastalert']['conf_dir']}/config/#{config_file}" do
    source "#{config_file}.erb"
    notifies :restart, 'docker_container[elastalert]', :delayed
  end
end

if node['elastalert']['rules'] then
  node['elastalert']['rules'].each_key do |name|
    # Retrieve configuration common for all rules and mix it in
    node.default['elastalert']['rules'][name] = node['elastalert']['rule_globals'] if node['elastalert']['rule_globals']
    # Convert rule definition to YAML, it tales two steps
    mutable_hash = JSON.parse(node['elastalert']['rules'][name].dup.to_json)
    yml_rule_config = mutable_hash.to_yaml
    file "#{node['elastalert']['conf_dir']}/rules/#{name}-rule.yaml" do
      content yml_rule_config
      mode 0644
      notifies :restart, 'docker_container[elastalert]', :delayed
    end
  end
end

# Start elastalert container
docker_container 'elastalert' do
  repo "#{node["docker"]["registry"]}/#{node['docker']['elastalert']['image']}"
  volumes [ "#{node['elastalert']['log_dir']}:/opt/logs:rw", "#{node['elastalert']['conf_dir']}/config/:/opt/config:ro", "#{node['elastalert']['conf_dir']}/rules/:/opt/rules:ro"  ]
  env [ "SET_CONTAINER_TIMEZONE=#{node['elastalert']['set_time_zone']}", "CONTAINER_TIMEZONE=#{node['elastalert']['time_zone']}",
        "ELASTICSEARCH_HOST=#{node['elastalert']['es_host']}", "ELASTICSEARCH_PORT=#{node['elastalert']['es_port']}" ]
  tag node['docker']['elastalert']['tag']
end
