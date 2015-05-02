#
# Cookbook Name:: delivery-cluster
# Recipe:: setup_analytics
#
# Author:: Salim Afiune (<afiune@chef.io>)
#
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'delivery-cluster::_settings'

# There are two ways to provision the Analytics Server
#
# 1) Provisioning the entire `delivery-cluster::setup` or
# 2) Just the Chef Server `delivery-cluster::setup_chef_server`
#
# After that you are good to provision Analytics running:
# => # bundle exec chef-client -z -o delivery-cluster::setup_analytics -E test

machine analytics_server_hostname do
  chef_server lazy { chef_server_config }
  provisioning.specific_machine_options('analytics').each do |option|
    add_machine_options option
  end
  files lazy {{
    "/etc/chef/trusted_certs/#{chef_server_ip}.crt" => "#{Chef::Config[:trusted_certs_dir]}/#{chef_server_ip}.crt"
  }}
  action :converge
end

# Activate Analytics
activate_analytics

# Configuring Analytics on the Chef Server
machine chef_server_hostname do
  recipe "chef-server-12::analytics"
  attributes lazy { chef_server_attributes }
  converge true
  action :converge
end

%w{ actions-source.json webui_priv.pem }.each do |analytics_file|
  machine_file "/etc/opscode-analytics/#{analytics_file}" do
    machine chef_server_hostname
    local_path "#{cluster_data_dir}/#{analytics_file}"
    action :download
  end
end

# Installing Analytics
machine analytics_server_hostname do
  chef_server lazy { chef_server_config }
  recipe "delivery-cluster::analytics"
  files(
    '/etc/opscode-analytics/actions-source.json' => "#{cluster_data_dir}/actions-source.json",
    '/etc/opscode-analytics/webui_priv.pem' => "#{cluster_data_dir}/webui_priv.pem"
  )
  attributes lazy {{
    'delivery-cluster' => {
      'analytics' => {
        'fqdn' => analytics_server_ip,
        'features' => is_splunk_enabled? ? 'true' : 'false'
      }
    }
  }}
  converge true
  action :converge
end

machine_file 'analytics-server-cert' do
  chef_server lazy { chef_server_config }
  path lazy { "/var/opt/opscode-analytics/ssl/ca/#{analytics_server_ip}.crt" }
  machine analytics_server_hostname
  local_path lazy { "#{Chef::Config[:trusted_certs_dir]}/#{analytics_server_ip}.crt" }
  action :download
end

# Add Analytics Server to the knife.rb config file
render_knife_config
