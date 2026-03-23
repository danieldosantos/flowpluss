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
            username: __ADMIN_USER__,
            password: __ADMIN_HASH__,
            permissions: "*"
        }]
    },

    credentialSecret: __CREDENTIAL_SECRET__,

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
