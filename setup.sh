#!/bin/bash

# Exit on error
set -e

# Variables - MODIFY THESE
PROJECT_NAME="my-bagisto"
PROJECT_PATH="/var/www/$PROJECT_NAME"
DOMAIN="your-domain.com"
DB_USER="bagisto"
DB_PASSWORD="your_password"
DB_NAME="bagisto"

# Function to check if command succeeded
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed"
        exit 1
    fi
}

# Function to print section headers
print_section() {
    echo "----------------------------------------"
    echo "$1"
    echo "----------------------------------------"
}

print_section "Starting Bagisto Installation"

# Update system
print_section "Updating System"
sudo apt update && sudo apt upgrade -y
check_command "System update"

# Add PHP repository
print_section "Adding PHP Repository"
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
check_command "PHP repository addition"

# Install PHP and required extensions
print_section "Installing PHP and Extensions"
sudo apt install -y php8.2 php8.2-common php8.2-cli php8.2-fpm \
    php8.2-intl php8.2-gd php8.2-curl php8.2-mbstring \
    php8.2-xml php8.2-zip php8.2-mysql php8.2-bcmath
check_command "PHP installation"

# Install MySQL
print_section "Installing MySQL"
sudo apt install -y mysql-server
check_command "MySQL installation"

# Secure MySQL installation
sudo mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"
check_command "MySQL configuration"

# Install Composer
print_section "Installing Composer"
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
check_command "Composer installation"

# Install Node.js
print_section "Installing Node.js"
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
check_command "Node.js installation"

# Install Nginx
print_section "Installing Nginx"
sudo apt install -y nginx
check_command "Nginx installation"

# Remove default Nginx configuration
print_section "Removing Default Nginx Configuration"
sudo rm -f /etc/nginx/sites-enabled/default
check_command "Default Nginx config removal"

# Create Bagisto project
print_section "Creating Bagisto Project"
cd /var/www
composer create-project bagisto/bagisto $PROJECT_NAME
check_command "Bagisto project creation"

# Configure Nginx
print_section "Configuring Nginx"
sudo tee /etc/nginx/sites-available/bagisto << EOL
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_PATH/public;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/bagisto_error.log;
    access_log /var/log/nginx/bagisto_access.log;
}
EOL

# Enable Nginx configuration
sudo ln -sf /etc/nginx/sites-available/bagisto /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
check_command "Nginx configuration"

# Configure environment
print_section "Configuring Environment"
cd $PROJECT_PATH
cp .env.example .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
check_command "Environment configuration"

# Install dependencies and build assets
print_section "Installing Dependencies and Building Assets"
composer install
check_command "Composer dependencies installation"

# Fix for laravel-vite-plugin ESM issue
npm install
npm install --save-dev @vitejs/plugin-vue
npm install --save-dev vite

# Update vite.config.js
cat > vite.config.js << EOL
import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
    plugins: [
        laravel({
            input: [
                'resources/css/app.css',
                'resources/js/app.js'
            ],
            refresh: true,
        }),
        vue({
            template: {
                transformAssetUrls: {
                    base: null,
                    includeAbsolute: false,
                },
            },
        }),
    ],
    resolve: {
        alias: {
            vue: 'vue/dist/vue.esm-bundler.js',
        },
    },
});
EOL

# Build assets
npm run build || {
    echo "First build attempt failed, trying alternative build..."
    npm run prod
}
check_command "Asset building"

# Generate application key
php artisan key:generate
check_command "Key generation"

# Run migrations and seeders
print_section "Setting up Database"
php artisan migrate
check_command "Database migration"
php artisan db:seed
check_command "Database seeding"
php artisan storage:link
check_command "Storage linking"

# Set permissions
print_section "Setting Permissions"
sudo chown -R www-data:www-data $PROJECT_PATH
sudo chmod -R 755 $PROJECT_PATH
sudo chmod -R 777 $PROJECT_PATH/storage
sudo chmod -R 777 $PROJECT_PATH/bootstrap/cache
check_command "Permission setting"

# Verify Nginx configuration and restart
print_section "Verifying Nginx Configuration"
sudo nginx -t
sudo systemctl restart nginx
check_command "Nginx verification"

print_section "Installation Complete!"
echo "Your Bagisto installation is available at: http://$DOMAIN"
echo "Admin panel: http://$DOMAIN/admin"
echo "Default admin credentials:"
echo "Email: admin@example.com"
echo "Password: admin123"
echo ""
echo "Please change the admin credentials after logging in!"
echo "Don't forget to set up SSL/HTTPS for production use."

# Final checks
echo ""
echo "Final Configuration Checks:"
echo "1. Nginx sites-enabled directory contents:"
ls -l /etc/nginx/sites-enabled/
echo ""
echo "2. PHP-FPM status:"
sudo systemctl status php8.2-fpm | grep Active
echo ""
echo "3. Nginx status:"
sudo systemctl status nginx | grep Active
