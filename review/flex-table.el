;;; flex-table.el --- Emacs 31's flex scoring against emacs-cpp's match tiers  -*- lexical-binding: t; -*-

;; From the repository root:  emacs -Q --batch -l review/flex-table.el [CORPUS-DIR]
;; Reads lisp/init-completion.el and evaluates its matcher definitions only (the defun,
;; defvar and defconst forms; no use-package form runs). Prints three things.
;; 1. The spec of test/init-completion-test.el (D-120): every input of it against every
;;    candidate of it that flex matches: emacs-cpp's tier and Emacs 31's flex cost
;;    (`completion--flex-cost', the Gotoh alignment in C, under `completion-ignore-case';
;;    lower is better). A pair of candidates with different tiers "agrees" when the lower
;;    tier has the lower cost, "ties" at equal cost, "disagrees" otherwise. Inputs with a
;;    space are skipped: flex has no words, orderless splits them before either ranker.
;; 2. The spec's sort example in flex's order, against the order the spec requires.
;; 3. Timings: the tier sort over CORPUS-DIR's file names (relative paths; default
;;    corpus/dealii-9.7.1, the 35000-name case of DESIGN 7), interpreted and byte-compiled,
;;    and the flex cost over the same names; best of 5 runs, `benchmark-run'.

(require 'cl-lib)
(require 'subr-x)

(defconst flex-table-spec
  '(("vec" "Vector.cc" 1) ("vec" "src/vector.h" 1) ("ser" "HTTPServer" 1)
    ("tools" "VectorTools.cc" 1) ("ector" "Vector.cc" 2)
    ("vt" "VectorTools.cc" 2) ("VT" "VectorTools.cc" 2)
    ("eto" "Vector.cc" 3) ("vec eto" "Vector.cc" 3) ("" "Vector.cc" 1)
    ("vfoo" "ATVfoo" 1) ("tv" "ATVfoo" 2) ("s" "HTTPServer" 1)
    ("hs" "HTTPServer" 2) ("n" "max_n" 1))
  "The rows of `init-completion-match-tiers' at c031e2b.")

(defconst flex-table-sort-example
  '("eto" ("Vector.cc" "fetor.c" "eto.h" "veto.h" "Petrol.cc")
    ("eto.h" "fetor.c" "veto.h" "Vector.cc" "Petrol.cc"))
  "Input, candidates in their given order, the order the spec requires.")

(defun flex-table-load-matcher (file)
  "Evaluate the definitions of FILE whose head is defun, defvar or defconst."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((n 0))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (memq (car-safe form) '(defun defvar defconst))
                (eval form t)
                (setq n (1+ n)))))
        (end-of-file nil))
      n)))

(defun flex-table-cost (input candidate)
  "Flex's normalized cost of CANDIDATE for INPUT, or nil.
Under `completion-ignore-case', as the tiers ignore case."
  (let ((completion-ignore-case t))
    (car (completion--flex-cost input candidate t))))

(defun flex-table-spec-section ()
  (let ((candidates (delete-dups (mapcar #'cadr flex-table-spec)))
        (inputs (delete-dups (mapcar #'car flex-table-spec)))
        (sum-agree 0) (sum-tie 0) (sum-disagree 0))
    (princ "1. spec inputs against spec candidates: tier (emacs-cpp) and flex cost\n")
    (dolist (input inputs)
      (cond
       ((string-empty-p input) (princ "  input \"\": skipped (tier 1 by definition; flex matches everything at cost 0)\n"))
       ((string-search " " input) (princ (format "  input %S: skipped (words; flex has none)\n" input)))
       (t
        (let (rows (agree 0) (tie 0) (disagree 0))
          (dolist (c candidates)
            (let ((cost (flex-table-cost input c)))
              (when cost
                (push (list c (emacs-cpp-match-tier input c) cost) rows))))
          (setq rows (sort rows (lambda (a b) (< (nth 2 a) (nth 2 b)))))
          (princ (format "  input %S, flex's order:\n" input))
          (dolist (r rows)
            (princ (format "    tier %d  cost %5d  %s\n" (nth 1 r) (nth 2 r) (nth 0 r))))
          (cl-loop for (a . rest) on rows do
                   (dolist (b rest)
                     (cond ((= (nth 1 a) (nth 1 b)))
                           ((= (nth 2 a) (nth 2 b)) (cl-incf tie))
                           ((eq (< (nth 1 a) (nth 1 b)) (< (nth 2 a) (nth 2 b))) (cl-incf agree))
                           (t (cl-incf disagree)
                              (princ (format "    DISAGREE: tier %d %s costs %d, tier %d %s costs %d\n"
                                             (nth 1 a) (nth 0 a) (nth 2 a) (nth 1 b) (nth 0 b) (nth 2 b)))))))
          (princ (format "    pairs across tiers: %d agree, %d tie, %d disagree\n" agree tie disagree))
          (cl-incf sum-agree agree) (cl-incf sum-tie tie) (cl-incf sum-disagree disagree)))))
    (princ (format "  total: %d agree, %d tie, %d disagree\n" sum-agree sum-tie sum-disagree))))

(defun flex-table-sort-section ()
  (pcase-let ((`(,input ,given ,required) flex-table-sort-example))
    (let* ((completion-ignore-case t)
           (by-flex (sort (copy-sequence given)
                          :key (lambda (c) (car (completion--flex-cost input c t)))))
           (by-tier (emacs-cpp-match-sort-by-tier input (copy-sequence given))))
      (princ (format "2. sort example, input %S\n   required: %S\n   tiers:    %S\n   flex:     %S (costs %S)\n"
                     input required by-tier by-flex
                     (mapcar (lambda (c) (car (completion--flex-cost input c t))) by-flex))))))

(defun flex-table-names (dir)
  (let ((root (file-name-as-directory (expand-file-name dir))))
    (mapcar (lambda (f) (string-remove-prefix root f))
            (directory-files-recursively root "" nil))))

(defun flex-table-best-of (n thunk)
  (let ((best most-positive-fixnum))
    (dotimes (_ n best)
      (setq best (min best (car (benchmark-run 1 (funcall thunk))))))))

(defun flex-table-timing-section (dir root)
  (let* ((names (flex-table-names dir))
         (dir (file-relative-name dir root))
         (inputs '("vec" "tria" "fe"))
         (n (length names)))
    (princ (format "3. timings over %d names of %s (best of 5, seconds)\n" n dir))
    (princ (format "   %-8s %12s %12s %12s\n" "input" "tier-interp" "tier-compiled" "flex-cost"))
    (let ((interp (mapcar (lambda (input)
                            (flex-table-best-of 5 (lambda () (emacs-cpp-match-sort-by-tier input (copy-sequence names)))))
                          inputs)))
      (dolist (f '(emacs-cpp--match-class emacs-cpp--match-word-start emacs-cpp--match-compile
                   emacs-cpp-match-tier emacs-cpp-match-sort-by-tier))
        (byte-compile f))
      (cl-loop for input in inputs for ti in interp do
               (let ((tc (flex-table-best-of 5 (lambda () (emacs-cpp-match-sort-by-tier input (copy-sequence names)))))
                     (fl (flex-table-best-of 5 (lambda () (let ((completion-ignore-case t))
                                                             (dolist (s names) (completion--flex-cost input s t)))))))
                 (princ (format "   %-8s %12.4f %12.4f %12.4f\n" input ti tc fl)))))))

(let* ((root (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))
       (corpus (or (car command-line-args-left) (expand-file-name "../corpus/dealii-9.7.1" root)))
       (n (flex-table-load-matcher (expand-file-name "lisp/init-completion.el" root))))
  (setq command-line-args-left nil)
  (princ (format "flex-table: %s, %d definitions from lisp/init-completion.el\n" (emacs-version) n))
  (flex-table-spec-section)
  (flex-table-sort-section)
  (flex-table-timing-section corpus root))
