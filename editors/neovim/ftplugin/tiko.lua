-- Buffer settings for tiko files. The language server does the rest.
if vim.b.did_ftplugin then return end
vim.b.did_ftplugin = true

-- ' starts a comment; /' ... '/ is a block comment.
vim.bo.commentstring = "' %s"
vim.bo.comments = "s1:/',mb: ,ex:'/,:'"

-- A name may end in a type suffix: Name$, Count%, Total&, Ratio!, Value#.
vim.opt_local.iskeyword:append({ '$', '%', '&', '!', '#' })

vim.b.undo_ftplugin = 'setlocal commentstring< comments< iskeyword<'
