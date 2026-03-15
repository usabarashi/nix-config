# see: https://neovim.io/
# see: https://github.com/rockerBOO/awesome-neovim
# see: https://github.com/nix-community/home-manager/blob/master/modules/programs/neovim.nix
{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;

    extraConfig = ''
      " Set leader key to Space
      let mapleader = " "

      " Buffer navigation with Tab
      nnoremap <Tab> :bnext<CR>
      nnoremap <S-Tab> :bprevious<CR>

      " Window navigation with Leader + hjkl
      nnoremap <leader>h <C-w>h
      nnoremap <leader>j <C-w>j
      nnoremap <leader>k <C-w>k
      nnoremap <leader>l <C-w>l

      noremap j gj
      noremap k gk

      " Enable 24-bit color first
      set termguicolors

      set cursorline
      set cursorcolumn
      set confirm
      set number
      set relativenumber
      set clipboard+=unnamedplus
      set wildmenu
      set wildmode=longest:full,full
      set undofile
      set nowrap
      set cmdheight=0
      set noshowmode

      " Search settings
      set ignorecase
      set smartcase
      set hlsearch
      set incsearch

      " Indent settings
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set smartindent

      " Scroll offset
      set scrolloff=8

      " Show buffer list in tabline
      set showtabline=2

      " Custom tabline to show buffers
      function! MyTabLine()
        let s = '''
        for i in range(1, bufnr('$'))
          if bufexists(i) && buflisted(i)
            let s .= (i == bufnr('%') ? '%#TabLineSel#' : '%#TabLine#')
            let s .= ' ' . i . ':'
            let name = bufname(i)
            let name = fnamemodify(name, ':t')
            if name == '''
              let name = '[No Name]'
            endif
            let s .= name . ' '
          endif
        endfor
        let s .= '%#TabLineFill#'
        return s
      endfunction
      set tabline=%!MyTabLine()

      " netrw (built-in file explorer) settings
      let g:netrw_liststyle = 3        " tree view
      let g:netrw_banner = 0           " hide banner
      let g:netrw_winsize = 25         " window width 25%
      let g:netrw_browse_split = 0     " open in same window
      let g:netrw_altv = 1             " split to the right

      " Open netrw with Space + e
      nnoremap <leader>e :Lexplore<CR>

      " Color scheme
      set background=dark
      colorscheme tokyonight-night

      " Status line at bottom (standard placement)
      function! CurrentMode()
        let l:modes = {
        \ 'n': 'NORMAL',
        \ 'i': 'INSERT',
        \ 'v': 'VISUAL',
        \ 'V': 'V-LINE',
        \ "\<C-v>": 'V-BLOCK',
        \ 'R': 'REPLACE',
        \ 't': 'TERMINAL',
        \ }
        let l:mode = mode()
        return get(l:modes, l:mode, l:mode)
      endfunction
      set statusline=%{CurrentMode()}\ \|\ %f\ %m%r%h%w\ [%Y]\ [%{&ff}]\ %=%l/%L:%c\ %p%%
      set laststatus=2
    '';

    plugins = with pkgs.vimPlugins; [
      vim-nix
      tokyonight-nvim
    ];
  };

}
