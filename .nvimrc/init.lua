local dap = require("dap")

vim.keymap.set("n", "<M-m>", function()
	vim.cmd("Compile bin/build.sh")
end, {})

dap.adapters.codelldb = {
	type = "server",
	port = "${port}",
	executable = {
		command = "codelldb",
		args = { "--port", "${port}" },
	},
}

dap.configurations.odin = {
	{
		name = "Debug Game (codelldb)",
		type = "codelldb",
		request = "launch",
		program = vim.fn.getcwd() .. "/target/game",
		cwd = vim.fn.getcwd(),
		stopOnEntry = false,
	},
}
