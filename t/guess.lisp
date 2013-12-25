#|
  This file is a part of guess project.
|#

(in-package :cl-user)
(defpackage guess-test
  (:use :cl
        :guess
        :cl-test-more))
(in-package :guess-test)

(plan nil)

;; http://lispuser.net/commonlisp/japanese.html#sec-2.1
(macrolet ((guess-jp (str &optional enc)
             `(dolist (ef #+allegro   '(:euc-jp :shiftjis :utf-8 :jis)
                          #+lispworks '(:euc-jp :shift-jis :utf-8 :jis)
                          #+clisp     '(charset:euc-jp charset:shift-jis charset:utf-8 charset:iso-2022-jp)
                          #+sbcl      '(:euc-jp :sjis :utf-8)
                          #+ccl       '(:euc-jp :cp932 :utf-8))
                (let ((vec #+allegro   (excl:string-to-octets ,str :external-format ef :null-terminate nil)
                           #+lispworks (external-format:encode-lisp-string ,str ef)
                           #+clisp     (ext:convert-string-to-bytes ,str ef)
                           #+sbcl      (sb-ext:string-to-octets ,str :external-format ef)
                           #+ccl       (ccl:encode-string-to-octets ,str :external-format ef)))
                  (let ((ret (ces-guess-from-vector vec :jp)))
                    (diag (format nil "~A => ~A (~A) => ~A~%" ,str vec ef ret))
                    (is ret ,(or enc 'ef)))))))
  (deftest
      ces-guess-jp
      (diag "* ces-guess-from-vector (jp)")  

    (dolist (str '("こんにちは" "地球" "今日はいい天気"))
      (guess-jp str))

    (guess-jp "this is a pen." :utf-8)))

(finalize)
