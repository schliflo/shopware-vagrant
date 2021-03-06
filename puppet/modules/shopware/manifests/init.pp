class shopware {

	package { ['npm']:
		ensure => present,
	}

	exec { 'install-grunt':
		cwd     => '/usr/bin/',
		command => 'ln -sf nodejs node;
			npm install -g grunt-cli',
		require => [Package['npm']],
		unless  => 'test -f /usr/local/bin/grunt',
	}

	exec { 'install-grunt-local':
		cwd     => "${document_root}/themes",
		command => "mkdir -p /home/vagrant/node_modules;
			ln -sf /home/vagrant/node_modules ${document_root}/themes/node_modules;
			npm install",
		require => [Exec['install-grunt']],
		unless  => 'test -e /home/vagrant/node_modules/grunt/',
	}

	exec { 'generate-md5':
		cwd     => "${document_root}",
		command => 'find engine/Shopware/ -type f -name "*.php" -printf "engine/Shopware/%P\n" | xargs -I {} md5sum {} > engine/Shopware/Components/Check/Data/Files.md5sums',
		unless  => "test -f engine/Shopware/Components/Check/Data/Files.md5sums",
	}

	exec { 'patch-install':
		cwd => "${document_root}",
		command => 'patch -p1 < /vagrant/provision/install.patch',
		onlyif  => 'test `grep -c "config_development.php" recovery/install/config/production.php` -eq 0',
	}

	if $browsersync {
		exec { 'patch-browsersync':
			cwd     => "${document_root}",
			command => 'patch -p1 < /vagrant/provision/browersync.patch',
			onlyif  => 'test `grep -c "browserSync" themes/Gruntfile.js` -eq 0',
			before  => Exec['install-grunt-local'],
		}
	}

	exec { 'set-version':
		cwd => "${document_root}",
		command => 'sed -i "s/___VERSION___/`git describe --abbrev=0 --tags | sed \'s/v//g\'`/g;s/___VERSION_TEXT___//g;s/___REVISION___/`php -r \'echo date("YmdHm",$argv[1]);\' $(git log -n1 --format="%at")`/g" engine/Shopware/Application.php recovery/install/data/version',
		onlyif  => 'test `grep -c "___VERSION___" engine/Shopware/Application.php` -ne 0',
		require => [Package['php5-cli'], Package['git']]
	}

	mysql::db { 'shopware':
		ensure   => 'present',
		user     => 'shopware',
		password => 'password',
		host     => 'localhost',
		grant    => ['all'],
		charset  => 'utf8',
	}

	mysql_user { "shopware@%":
		ensure        => present,
		password_hash => mysql_password("password"),
		require       => [Mysql::Db['shopware']],
	}

	mysql_grant { 'shopware@%/shopware.*':
		ensure     => 'present',
		options    => ['GRANT'],
		privileges => ['ALL'],
		table      => 'shopware.*',
		user       => 'shopware@%',
		require    => [Mysql::Db['shopware']],
	}

	mysql_user { "root@%":
		ensure        => present,
		password_hash => mysql_password("password"),
		require       => [Mysql::Db['shopware']],
	}

	mysql_grant { "root@%/*.*":
		user       => 'root@%',
		privileges => "all",
		table      => '*.*',
		require    => Mysql_user["root@%"],
	}

	exec { 'installDB':
		cwd     => "${document_root}",
		command => 'mysql -u shopware -ppassword shopware < _sql/install/latest.sql;
			./build/ApplyDeltas.php --username="shopware" --password="password" --host="localhost" --dbname="shopware" --mode=install;
			./bin/console sw:generate:attributes;
			./bin/console sw:snippets:to:db --include-plugins;
			rm recovery/install/data/dbsetup.lock',
		require => [Exec['installIonCube'], Mysql_user["shopware@%"], Mysql_grant["shopware@%/shopware.*"]],
		onlyif  => 'test -e recovery/install/data/dbsetup.lock',
	}

	exec{ 'installIonCube':
		command => 'wget http://downloads3.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz;
			tar xf ioncube_loaders_lin_x86-64.tar.gz -C /usr/local/;
			rm ioncube_loaders_lin_x86-64.tar.gz',
		unless  => 'test -f /usr/local/ioncube/ioncube_loader_lin_5.6.so',
		require => [Package['php5-fpm'], Package['wget']],
		notify  => Service['php5-fpm'],
	}

	file { '/etc/php5/mods-available/ioncube.ini':
		content => "; priority=05\nzend_extension=/usr/local/ioncube/ioncube_loader_lin_5.6.so",
		ensure  => present,
		require => Exec['installPhpXdebug'],
	}

	file { ["${document_root}/config_development.php", "${document_root}/config.php"]:
		content => template('shopware/config.erb')
	}

	exec { 'enableIonCube':
		command => 'php5enmod ioncube',
		require => [ File['/etc/php5/mods-available/ioncube.ini']],
		notify  => Service['php5-fpm'],
		unless  => 'php -i | grep -q "ionCube Loader"'
	}

	file { [
		"${document_root}/web",
		"${document_root}/web/cache",
		"${document_root}/var",
		"${document_root}/var/cache",
		"${document_root}/var/log",
		"${document_root}/files",
		"${document_root}/files/documents",
		"${document_root}/files/downloads",
		"${document_root}/media",
		"${document_root}/media/archive",
		"${document_root}/media/image",
		"${document_root}/media/image/thumbnail",
		"${document_root}/media/music",
		"${document_root}/media/pdf",
		"${document_root}/media/unknown",
		"${document_root}/media/video",
		"${document_root}/media/temp",
		"${document_root}/engine",
		"${document_root}/engine/Shopware",
		"${document_root}/engine/Shopware/Plugins",
		"${document_root}/engine/Shopware/Plugins/Community",
		"${document_root}/engine/Shopware/Plugins/Community/Frontend",
		"${document_root}/engine/Shopware/Plugins/Community/Core",
		"${document_root}/engine/Shopware/Plugins/Community/Backend"
	]:
		ensure => directory,
	}

}
