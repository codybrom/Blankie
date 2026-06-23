# Blankie Documentation Dockerfile
# 
# Run with Docker Compose (recommended):
#   docker-compose up
#
# Or run standalone:
#   docker build -t blankie-docs .
#   docker run -p 4321:4321 -v $(pwd)/..:/parent:ro blankie-docs

FROM node:24-alpine

WORKDIR /app

ENV NODE_ENV=development

# Install dependencies first (better caching)
COPY package.json package-lock.json ./
RUN npm ci

# Copy all docs files
COPY . .

# Create directories for parent files
RUN mkdir -p /Blankie/Resources

EXPOSE 4321

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:4321', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"

CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]