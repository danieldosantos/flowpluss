module.exports = {
    flowFile: 'flows.json',

    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",

    httpAdminRoot: '/',
    httpNodeRoot: '/',

    functionGlobalContext: {},

    adminAuth: {
        type: "credentials",
        users: [{
            username: "admin",
            password: "$2b$08$z7lqgYpCzG1p4k6Yx4QY3uW3mZ1k5Y3Q8G2yH7L3QFZkP5rV6p1yG",
            permissions: "*"
        }]
    },

    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET || "supersecretkey",

    httpNodeCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    },

    contextStorage: {
        default: "memory",
        memory: {
            module: "memory"
        }
    },

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    functionTimeout: 10,

    editorTheme: {
        projects: {
            enabled: false
        }
    }
};