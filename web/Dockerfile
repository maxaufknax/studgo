FROM nginx:alpine
COPY nginx-site.conf /etc/nginx/conf.d/default.conf
COPY security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY index.html datenschutz.html robots.txt /usr/share/nginx/html/
COPY assets/ /usr/share/nginx/html/assets/
