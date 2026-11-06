FROM node:20-slim
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js tracing.js ./
COPY public ./public
EXPOSE 3000
CMD ["node", "-r", "./tracing.js", "server.js"]
