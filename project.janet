(declare-project
  :name "janet-subprocess-notes"
  :url "https://github.com/sogaiu/janet-subprocess-notes"
  :dependencies ["https://github.com/bakpakin/mendoza"])

(task "watch" []
  (os/execute ["mdz" "watch"] :p))
