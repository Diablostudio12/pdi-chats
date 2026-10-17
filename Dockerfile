FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY app/ .
RUN flutter create --platforms=web --project-name pdi_chats . \
 && flutter pub get \
 && flutter build web --release

FROM nginx:alpine
ENV PORT=8080
COPY web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html
