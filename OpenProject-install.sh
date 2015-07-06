#!/bin/bash

# This is pretty much a concatenated list of commands from this page:
# https://www.openproject.org/projects/openproject/wiki/Installation_on_Centos_65_x64_with_Apache_and_PostgreSQL_93
# 
# The order is not exactly the same, because I wanted to make the
# process a bit faster.  For example, running yum is heavy, so I try to
# run it fewer times.
# 
# The only difference is that it is MySQL powered, and not PostgreSQL.
# That idea I got from here:
# http://possiblelossofprecision.net/?p=1692
#

# Update your system
echo Step 1: Update your system
yum --assumeyes update
# Install tools needed for DB and Ruby
# Install some handy tools
# Install MySQL DB
# Install packages for Ruby
# Install Apache with Passenger 
echo Step 2: Install necessary packages
yum --assumeyes groupinstall "Development tools"
yum --assumeyes install \
	git wget \
	vim mlocate \
	mysql-server \
	\
	libyaml libxml2 libxml2-devel libxslt-devel libxml2-devel \
	ruby-mysql mysql-devel \
	ImageMagick-c++ ImageMagick-devel \
	graphviz graphviz-ruby graphviz-devel \
	memcached \
	sqlite-devel \
	\
	httpd curl-devel httpd-devel apr-devel apr-util-devel
	

# Create dedicate user and group
echo Step 3: Create user and group for openproject
groupadd openproject
useradd -d /opt/openproject -g openproject openproject
echo "openproject\nopenproject" | (passwd --stdin openproject)

# Create the script to run as openproject (Part 1)
read -d '' SCRIPT <<"EOF"
	# Load profile
	cd ~
	echo "source ~/.profile" >> ~/.bash_profile
	source ~/.profile

	# Install RVM (Ruby Version Manager)
	gpg2 --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
	curl --silent --location https://get.rvm.io | bash -s stable
	source $HOME/.rvm/scripts/rvm

	# Install Ruby via RVM
	rvm autolibs disable
	rvm install 2.1.0 
	gem install bundler

	# Install OpenProject
	git clone https://github.com/opf/openproject.git
	cd openproject
	git checkout stable
	bundle install --without postgres
	cp config/database.yml.example config/database.yml
	cp config/configuration.yml.example config/configuration.yml
EOF

echo Step 4: Install OpenProject - part 1
su - openproject -c "echo $SCRIPT | bash -l"

# Grant permission to Passenger
chmod o+x "/opt/openproject" 

cd /opt/openproject/openproject/

# Create the plugin gems file
read -d '' PLUGINS <<"EOF"
gem "pdf-inspector", "~>1.0.0", :group => :test
gem "openproject-backlogs", :git => "https://github.com/finnlabs/openproject-backlogs.git", :branch => 'stable'
gem "openproject-pdf_export", :git => "https://github.com/finnlabs/openproject-pdf_export.git", :branch => 'stable'
gem 'openproject-costs', :git => 'https://github.com/finnlabs/openproject-costs.git', :branch => 'stable'
gem 'openproject-global_roles', :git => 'https://github.com/finnlabs/openproject-global_roles.git', :branch => 'stable'
gem 'openproject-help_link', :git => 'https://github.com/finnlabs/openproject-help_link.git', :branch => 'stable'
gem 'openproject-meeting', :git => 'https://github.com/finnlabs/openproject-meeting.git', :branch => 'stable'
gem 'openproject-my_project_page', :git => 'https://github.com/finnlabs/openproject-my_project_page.git', :branch => 'stable'
gem 'openproject-documents', :git => 'https://github.com/opf/openproject-documents.git', :branch => 'stable'
gem 'reporting_engine', :git => 'https://github.com/finnlabs/reporting_engine.git', :branch => 'dev'
gem 'openproject-reporting', :git => 'https://github.com/finnlabs/openproject-reporting.git', :branch => 'stable'
gem 'openproject-translations', :git => 'https://github.com/opf/openproject-translations.git', :branch => 'stable/4.1'
gem "openproject-auto_project", :git => "https://github.com/oliverguenther/openproject-auto_project.git", :branch => 'stable'
gem 'openproject-emoji',:git => 'https://github.com/tessi/openproject-emoji.git', :branch => 'stable'
gem "openproject-ensure_project_hierarchy", :git => "https://github.com/oliverguenther/openproject-ensure_project_hierarchy.git", :branch => 'stable'
gem "openproject-gitlab", git: "https://github.com/nietonfir/openproject-gitlab_integration.git", :branch=> "master" 
EOF

echo Step 5: Create Gemfile.plugins
su - openproject -c "echo $PLUGINS > ~/openproject/Gemfile.plugins"

# Create the script to run as openproject (Part 2)
read -d '' SCRIPT <<"EOF"
	cd ~/openproject
	bundle exec rake db:create:all
	bundle exec rake db:migrate
	bundle exec rake generate_secret_token
	RAILS_ENV="production" bundle exec rake db:seed
	RAILS_ENV="production" bundle exec rake db:migrate

	# Precompile assets
	RAILS_ENV="production" bundle exec rake assets:precompile
	
	# Install Passenger gem
	gem install passenger

	# Compile Passenger for Apache 
	passenger-install-apache2-module
EOF

echo Step 6: Install OpenProject - part 2
su - openproject -c "echo $SCRIPT | bash -l"

read -d '' CONF <<"EOF"
LoadModule passenger_module /opt/openproject/.rvm/gems/ruby-2.1.0/gems/passenger-4.0.37/buildout/apache2/mod_passenger.so
<IfModule mod_passenger.c>
	PassengerRoot /opt/openproject/.rvm/gems/ruby-2.1.0/gems/passenger-4.0.37
	PassengerDefaultRuby /opt/openproject/.rvm/gems/ruby-2.1.0/wrappers/ruby
</IfModule>
<VirtualHost *:80>
	ServerName www.myopenprojectsite.com
	# !!! Be sure to point DocumentRoot to 'public'!
	DocumentRoot /opt/openproject/openproject/public    
	<Directory /opt/openproject/openproject/public>
		# This relaxes Apache security settings.
		AllowOverride all
		# MultiViews must be turned off.
		Options -MultiViews
	</Directory>
</VirtualHost> 
EOF

echo Ste 7: Create Apache configuration
echo $CONF > /etc/httpd/conf.d/openproject.conf

echo Ste 8: Start services
setenforce 0
service iptables stop
service httpd restart
service mysqld restart

