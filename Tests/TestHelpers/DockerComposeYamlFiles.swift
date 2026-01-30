//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

public struct DockerComposeYamlFiles {
    public static let dockerComposeYaml1 = """
        version: '3.8'
        
        services:
          wordpress:
            image: wordpress:latest
            ports:
              - "8080:80"
            environment:
              WORDPRESS_DB_HOST: db
              WORDPRESS_DB_USER: wordpress
              WORDPRESS_DB_PASSWORD: wordpress
              WORDPRESS_DB_NAME: wordpress
            depends_on:
              - db
            volumes:
              - wordpress_data:/var/www/html
          
          db:
            image: mysql:8.0
            environment:
              MYSQL_DATABASE: wordpress
              MYSQL_USER: wordpress
              MYSQL_PASSWORD: wordpress
              MYSQL_ROOT_PASSWORD: rootpassword
            volumes:
              - db_data:/var/lib/mysql
        
        volumes:
          wordpress_data:
          db_data:
        """
    
    public static let dockerComposeYaml2 = """
        version: '3.8'
        name: webapp
        
        services:
          nginx:
            image: nginx:alpine
            ports:
              - "80:80"
            depends_on:
              - app
            networks:
              - frontend
          
          app:
            image: node:18-alpine
            working_dir: /app
            environment:
              NODE_ENV: production
              DATABASE_URL: postgres://db:5432/myapp
            depends_on:
              - db
              - redis
            networks:
              - frontend
              - backend
          
          db:
            image: postgres:14-alpine
            environment:
              POSTGRES_DB: myapp
              POSTGRES_USER: user
              POSTGRES_PASSWORD: password
            volumes:
              - db-data:/var/lib/postgresql/data
            networks:
              - backend
          
          redis:
            image: redis:alpine
            networks:
              - backend
        
        volumes:
          db-data:
        
        networks:
          frontend:
          backend:
        """
    
    public static let dockerComposeYaml3 = """
        version: '3.8'
        
        services:
          api-gateway:
            image: traefik:v2.10
            ports:
              - "81:80"
              - "8081:8080"
            depends_on:
              - auth-service
              - user-service
              - order-service
          
          auth-service:
            image: auth:latest
            environment:
              JWT_SECRET: secret123
              DATABASE_URL: postgres://db:5432/auth
          
          user-service:
            image: user:latest
            environment:
              DATABASE_URL: postgres://db:5432/users
          
          order-service:
            image: order:latest
            environment:
              DATABASE_URL: postgres://db:5432/orders
          
          db:
            image: postgres:14
            environment:
              POSTGRES_PASSWORD: postgres
        """
    
    public static let dockerComposeYaml4 = """
        version: '3.8'
        
        services:
          app:
            build:
              context: .
              dockerfile: Dockerfile.dev
            volumes:
              - ./app:/app
              - /app/node_modules
            environment:
              NODE_ENV: development
            ports:
              - "3000:3000"
            command: npm run dev
        """
    
    public static let dockerComposeYaml5 = """
        version: '3.8'
        
        services:
          app:
            image: myapp:latest
            configs:
              - source: app_config
                target: /etc/app/config.yml
            secrets:
              - db_password
        
        configs:
          app_config:
            external: true
        
        secrets:
          db_password:
            external: true
        """
    
    public static let dockerComposeYaml6 = """
        version: '3.8'
        
        services:
          web:
            image: nginx:latest
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost"]
              interval: 30s
              timeout: 10s
              retries: 3
              start_period: 40s
          
          db:
            image: postgres:14
            restart: always
            healthcheck:
              test: ["CMD-SHELL", "pg_isready -U postgres"]
              interval: 10s
              timeout: 5s
              retries: 5
        """
    
    public static let dockerComposeYaml7 = """
        version: '3.8'
        
        services:
          frontend:
            image: frontend:latest
            depends_on:
              - api
          
          api:
            image: api:latest
            depends_on:
              - cache
              - db
          
          cache:
            image: redis:alpine
          
          db:
            image: postgres:14
        """
    
    public static let dockerComposeYaml8 = """
    version: '3.8'

    services:
      web:
        image: nginx:alpine
        ports:
          - "8082:80"
        depends_on:
          - app

      app:
        image: python:3.12-alpine
        depends_on:
          - db
        command: python -m http.server 8000
        environment:
          DATABASE_URL: postgres://postgres:postgres@db:5432/appdb

      db:
        image: postgres:14
        environment:
          POSTGRES_DB: appdb
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
    """

    public static let dockerComposeYaml9 = """
    version: '3.8'
    services:
      web:
        image: nginx:alpine
        container_name: custom_nginx
        ports:
          - "8082:80"
    """
}
