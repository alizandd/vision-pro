/**
 * Server configuration
 */

module.exports = {
    // Server port - can be overridden with PORT environment variable
    port: process.env.PORT || 8080,

    // Server host - 0.0.0.0 allows connections from any network interface
    host: process.env.HOST || '0.0.0.0',

    // Heartbeat interval in milliseconds
    heartbeatInterval: 30000,

    // Maximum message size (10 MB)
    maxPayload: 10 * 1024 * 1024
};
