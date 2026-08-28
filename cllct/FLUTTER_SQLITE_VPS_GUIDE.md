# Flutter and SQLite in a VPS Guide

This guide provides a step-by-step process for setting up a Flutter application with a persistent SQLite database on a Virtual Private Server (VPS).

## Prerequisites

*   A VPS with a Linux distribution (e.g., Ubuntu).
*   SSH access to your VPS.
*   Basic knowledge of the Linux command line.

## 1. Set up the VPS

1.  **Connect to your VPS:**
    ```bash
    ssh your_username@your_vps_ip
    ```

2.  **Update the package list:**
    ```bash
    sudo apt update
    ```

3.  **Install necessary packages:**
    ```bash
    sudo apt install -y build-essential curl file git unzip
    ```

## 2. Install Flutter

1.  **Download the Flutter SDK:**

    Go to the [Flutter website](https://flutter.dev/docs/get-started/install/linux) and download the latest stable release of the Flutter SDK.

2.  **Extract the SDK:**
    ```bash
    tar xf flutter_linux_*.tar.xz
    ```

3.  **Add Flutter to your path:**
    ```bash
    echo 'export PATH="$PATH:`pwd`/flutter/bin"' >> ~/.bashrc
    source ~/.bashrc
    ```

4.  **Verify the installation:**
    ```bash
    flutter doctor
    ```

## 3. Set up the Backend

1.  **Install a web server (e.g., Nginx):**
    ```bash
    sudo apt install -y nginx
    ```

2.  **Create a server block for your application:**

    Create a new configuration file in `/etc/nginx/sites-available/`:
    ```bash
    sudo nano /etc/nginx/sites-available/cllct
    ```

    Add the following configuration:
    ```nginx
    server {
        listen 80;
        server_name your_domain.com;

        root /var/www/cllct;
        index index.html;

        location / {
            try_files $uri $uri/ =404;
        }
    }
    ```

3.  **Enable the server block:**
    ```bash
    sudo ln -s /etc/nginx/sites-available/cllct /etc/nginx/sites-enabled/
    ```

4.  **Test the Nginx configuration:**
    ```bash
    sudo nginx -t
    ```

5.  **Restart Nginx:**
    ```bash
    sudo systemctl restart nginx
    ```

## 4. Deploy the Application

1.  **Create a directory for your application:**
    ```bash
    sudo mkdir -p /var/www/cllct
    ```

2.  **Clone your repository:**
    ```bash
    git clone https://github.com/your_username/your_repository.git /var/www/cllct
    ```

3.  **Set the correct permissions:**
    ```bash
    sudo chown -R www-data:www-data /var/www/cllct
    ```

## 5. Set up the SQLite Database

Since `sql.js` is a client-side database, there is no need for a separate database server. The database is stored in the user's browser. If you want a persistent database on the server, you would need to implement a backend service (e.g., with Node.js, Python, or Go) that interacts with a server-side SQLite database.
