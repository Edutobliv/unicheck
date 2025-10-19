const path = require('path');
const YAML = require('yamljs');

const specPath = path.join(__dirname, '..', 'openapi.yaml');

try {
  YAML.load(specPath);
  console.log('OpenAPI parsed OK');
} catch (err) {
  console.error('Failed to parse openapi.yaml');
  console.error(err && err.stack ? err.stack : err);
  process.exitCode = 1;
}
