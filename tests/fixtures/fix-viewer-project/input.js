const rl = require("node:readline").createInterface({input: process.stdin, output: process.stdout}); rl.question("Name: ", name => { console.log("Hello " + name); rl.close(); });
