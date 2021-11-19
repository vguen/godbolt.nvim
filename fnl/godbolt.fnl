(local fun vim.fn)
(local api vim.api)
(local nsid (vim.api.nvim_create_namespace :godbolt))


(fn get-compiler-list [cmd]
  (var op [])
  (local jobid (vim.fn.jobstart cmd
                 {:on_stdout (fn [_ data _]
                               (vim.list_extend op data))}))
  (local t (vim.fn.jobwait [jobid]))
  (var final [])
  (each [k v (pairs op)]
    (if (not= k 1)
      (table.insert final v)))
  final)


(fn transform [entry]
  {:value (. (vim.split entry " ") 1)
   :display entry
   :ordinal entry})

; FIXME
(fn tscope [ft]

  (local pickers (require :telescope.pickers))
  (local finders (require :telescope.finders))
  (local conf (. (require :telescope.config) :values))
  (local actions (require :telescope.actions))
  (local actions-state (require :telescope.actions.state))

  (local ft (match ft
              :cpp :c++
              x x))
  (local cmd (string.format "curl https://godbolt.org/api/compilers/%s" ft))
  (local lines (get-compiler-list cmd))
  (var compiler nil)
  (: (pickers.new nil {:prompt_title "Choose compiler"
                       :finder (finders.new_table {:results lines
                                                   :entry_maker transform})
                       :sorter (conf.generic_sorter nil)
                       :attach_mappings (fn [prompt-bufnr map]
                                         (actions.select_default:replace (fn []
                                                                          (actions.close prompt-bufnr)
                                                                          (local selection (actions-state.get_selected_entry))
                                                                          (set compiler (. selection :value)))))})
     :find)
  compiler)

(var config
  {:cpp {:compiler :g112 :options nil}
   :c {:compiler :cg112 :options nil}
   :rust {:compiler :r1560 :options nil}})

(fn setup [cfg]
  (if vim.g.godbolt_loaded
    nil
    (do (global source-asm-bufs {})
        (if cfg (each [k v (pairs cfg)]
                  (tset config k v)))
        (set vim.g.godbolt_loaded true))))

(fn get [cmd]
  "Get the response from godbolt.org as a lua table"
  (var output_arr [])
  (local jobid (fun.jobstart cmd
                 {:on_stdout (fn [_ data _]
                               (vim.list_extend output_arr data))}))
  (local t (fun.jobwait [jobid]))
  (local json (fun.join output_arr))
  (fun.json_decode json))

(fn build-cmd [compiler text options]
  "Build curl command from compiler, text and flags"
  (local json (fun.json_encode
                {:source text
                 :options {:userArguments options}}))
  (string.format
    (.. "curl https://godbolt.org/api/compiler/'%s'/compile"
        " --data-binary '%s'"
        " --header 'Accept: application/json'"
        " --header 'Content-Type: application/json'")
    compiler json))

(fn get-compiler [compiler options]
  (if compiler
    (if (= :telescope compiler)
      (if options
        [(tscope vim.bo.filetype) options]
        [(tscope vim.bo.filetype) nil])
      (if options
        [compiler options]
        [compiler nil]))
    (do
      (local ft vim.bo.filetype)
      [(. config ft :compiler) (. config ft :options)])))

(fn setup-aucmd [buf offset]
  (vim.cmd "augroup Godbolt")
  (vim.cmd (string.format "autocmd CursorHold <buffer=%s> lua require('godbolt').highlight(%s, %s)" buf buf offset))
  (vim.cmd (string.format "autocmd CursorMoved,BufLeave <buffer=%s> lua require('godbolt').clear(%s)" buf buf))
  (vim.cmd "augroup END"))

(fn prepare-buf [text]
  (local buf (api.nvim_create_buf false true))
  (api.nvim_buf_set_option buf :filetype :asm)
  (api.nvim_buf_set_lines buf 0 0 false
    (vim.split text "\n" {:trimempty true}))
  buf)

(fn display [begin end compiler options]
  "Display assembly in a split"
  (if vim.g.godbolt_loaded
    (let [lines (api.nvim_buf_get_lines 0 (- begin  1) end true)
          text (fun.join lines "\n")
          chosen-compiler (get-compiler compiler options)
          response (get (build-cmd
                          (. chosen-compiler 1) text (. chosen-compiler 2)))
          asm (accumulate [str ""
                           k v (pairs (. response :asm))]
                (.. str "\n" (. v :text)))
          source-winid (fun.win_getid)
          source-bufnr (fun.bufnr)
          disp-buf (prepare-buf asm)]
      (vim.cmd :vsplit)
      (vim.cmd (string.format "buffer %d" disp-buf))
      (api.nvim_win_set_option 0 :number false)
      (api.nvim_win_set_option 0 :relativenumber false)
      (api.nvim_win_set_option 0 :spell false)
      (api.nvim_win_set_option 0 :cursorline false)
      (api.nvim_set_current_win source-winid)
      (tset source-asm-bufs source-bufnr [disp-buf (. response :asm)])
      (setup-aucmd source-bufnr begin))
    (vim.api.nvim_err_writeln "setup function not called")))

(fn clear [buf]
  (-> (. source-asm-bufs buf 1)
      (vim.api.nvim_buf_clear_namespace nsid 0 -1)))

(fn highlight [buf offset]
  (local disp-buf (. source-asm-bufs buf 1))
  (local asm-table (. source-asm-bufs buf 2))
  (local linenum (-> (fun.getcurpos) (. 2) (- offset) (+ 1)))
  (each [k v (pairs asm-table)]
    (if (= (type (. v :source)) :table)
      (if (= linenum (. v :source :line))
        (vim.highlight.range
         disp-buf nsid :Visual
         [(- k 1) 0] [(- k 1) 100]
         :linewise true)))))

{: display : highlight : clear : setup}
