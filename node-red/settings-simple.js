module.exports = {
    uiPort: 1880,
    
    credentialSecret: "__CREDENTIAL_SECRET__",
    
    adminAuth: {
        type: "credentials",
        users: [{
            username: "__ADMIN_USER__",
            password: "__ADMIN_HASH__",
            permissions: "*"
        }]
    },

    httpAdminCookieOptions: {
        httpOnly: true,
        sameSite: 'strict'
    },

    contextStorage: __CONTEXT_STORAGE_CONFIG__,

    functionTimeout: 10,

    editorTheme: {
        projects: {
            enabled: false
        }
    }
};
