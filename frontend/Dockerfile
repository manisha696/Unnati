# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Copy dependency specifications first
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy all source files and build web release
COPY . .
ARG API_BASE_URL=""
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

# Stage 2: Serve with lightweight NGINX
FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
