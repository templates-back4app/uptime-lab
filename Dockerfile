FROM node:22-alpine
WORKDIR /app
COPY app.js .
ENV PORT=8080
EXPOSE 8080
CMD ["node", "app.js"]
