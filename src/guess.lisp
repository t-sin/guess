;;; -*- mode: lisp; coding: utf-8 -*-
;;; 
;;; This code is derivative of libguess-1.0 and guess-0.1.0 for common lisp.
;;; 
;;; Copyright (c) 2011 zqwell <zqwell@gmail.com>
;;; 
;;; The following is the original copyright notice.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;; 
;;; 1. Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.
;;; 
;;; 2. Redistributions in binary form must reproduce the above copyright
;;;    notice, this list of conditions and the following disclaimer in the
;;;    documentation and/or other materials provided with the distribution.
;;; 
;;; 3. Neither the name of the authors nor the names of its contributors
;;;    may be used to endorse or promote products derived from this
;;;    software without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;; TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;; PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;; LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;; 
;;; Copyright (c) 2000-2003 Shiro Kawai, All rights reserved.
;;; 

(in-package :guess)

;; (declaim (optimize (speed 3) (space 0) (safety 0) (debug 0)))
;; (declaim (optimize (speed 0) (space 0) (safety 3) (debug 3)))

;;;; DFA Utility

(defmacro dfa-init (dfa-st dfa-ar dfa-name)
  `(vector ,dfa-st ,dfa-ar 0 1.0d0 ,dfa-name))

(defmacro dfa-name (dfa)   `(svref ,dfa 4))
(defmacro score (dfa)  `(svref ,dfa 3))
(defmacro state (dfa)  `(svref ,dfa 2))
(defmacro arcs (dfa)   `(svref ,dfa 1))
(defmacro states (dfa) `(svref ,dfa 0))

(defmacro dfa-alive (dfa) `(>= (the fixnum (state ,dfa)) (the fixnum 0)))

(defmacro dfa-next (dfa ch)
  `(when (dfa-alive ,dfa)
     (let ((temp (svref
		  (svref (states ,dfa) (state ,dfa))
		  ,ch)))
       (if (< (the fixnum temp) (the fixnum  0))
	   (setf (state ,dfa) -1)
	   (setf (state ,dfa) (the fixnum (car (svref (arcs ,dfa) temp)))
		 (score ,dfa) (* (the double-float (score ,dfa))
				 (the single-float (cdr (svref (arcs ,dfa) temp)))))))))

(defmacro dfa-process (order ch)
  (with-gensyms (gorder gch)
     `(let ((,gorder ,order)
	   (,gch ,ch))
	(or (loop for dfa in ,gorder
		  for i of-type fixnum from 0
		  do 
		     (when (dfa-alive dfa)
		       (when (dfa-alone dfa ,gorder)
			 (return (dfa-name dfa)))
		       (dfa-next (nth i ,gorder) ,gch)))
	    nil))))
  
(defun dfa-alone (dfa order)
  (unless (dfa-alive dfa)
    (return-from dfa-alone nil))
  (loop for d in order
	do (if (and (not (eql dfa d)) (dfa-alive d))
	       (return-from dfa-alone nil)))
  t)

(defun dfa-top (order)
  (let ((top nil))
    (loop for dfa in order do
      (if (and (dfa-alive dfa)
	       (or (null top)
		   (> (the double-float (score dfa)) (the double-float (score top)))))
	  (setf top dfa)))
    top))

(defun dfa-none (order)
  (dolist (d order)
    (if (dfa-alive d)
	(return-from dfa-none nil)))
  t)

(defmacro generate-order (&rest encodings)
  `(list
    ,@(mapcar (lambda (enc)
		(let ((dfa-st (find-symbol (string-upcase (format nil "+~A-ST+" (symbol-name enc))) :guess))
		      (dfa-ar (find-symbol (string-upcase (format nil "+~A-AR+" (symbol-name enc))) :guess))
		      (dfa-name (enc-name->keyword enc)))
		  `(dfa-init ,dfa-st ,dfa-ar ,dfa-name)))
		  encodings)))


;;;; export function

(defun ces-guess-from-vector (vector scheme)
  (case scheme
    (:jp (guess-jp vector)) ;; japanese 
    (:tw (guess-tw vector)) ;; taiwanese
    (:cn (guess-cn vector)) ;; chinese
    (:kr (guess-kr vector)) ;; korean 
    (:ru (guess-ru vector)) ;; russian
    (:ar (guess-ar vector)) ;; arabic 
    (:tr (guess-tr vector)) ;; turkish
    (:gr (guess-gr vector)) ;; greek  
    (:hw (guess-hw vector)) ;; hebrew 
    (:pl (guess-pl vector)) ;; polish 
    (:bl (guess-bl vector)) ;; baltic 
    (t   (error (format nil "scheme parameter (~A): not supported." scheme)))))


(defun guess-jp (buffer &aux (len (length buffer)))
  (block guess-body
    ;; (let* ((eucj (dfa-init +eucj-st+ +eucj-ar+ (euc-jp)))
    ;; 	      (sjis (dfa-init +sjis-st+ +sjis-ar+ (shiftjis)))
    ;; 	      (utf8 (dfa-init +utf8-st+ +utf8-ar+ (utf-8)))
    ;; 	      (top  nil))
    (let ((order (generate-order utf8 sjis eucj))
	  (c nil))
      (declare (dynamic-extent order))
      (loop for i of-type fixnum from 0 below len do
	(setf c (aref buffer (the fixnum i)))

	;; special treatment of iso-2022 escape sequence
	(when (and (= (the fixnum c) (the fixnum #x1b)) 
		   (< (the fixnum i) (the fixnum (1- len))))
	  (setf c (aref buffer (the fixnum (incf i))))
	  (when (or (= (the fixnum c) (the fixnum #x24))  ; $
		    (= (the fixnum c) (the fixnum #x28))) ; (
	    (return-from guess-body (iso-2022-jp-keyword))))

	;; special treatment of BOM
	(when (and (= (the fixnum i) (the fixnum 0))
		   (= (the fixnum c) (the fixnum #xff))
		   (< (the fixnum i) (the fixnum (1- len))))
	  (setf c (aref buffer (the fixnum (1+ i))))
	  (when (= (the fixnum c) #xfe)
	    (return-from guess-body (ucs-2le-keyword))))
	(when (and (= (the fixnum i) (the fixnum 0))
		   (= (the fixnum c) (the fixnum #xfe))
		   (< (the fixnum i) (the fixnum (1- len))))
	  (setf c (aref buffer (the fixnum (1+ i))))
	  (when (= (the fixnum c) #xff)
	    (return-from guess-body (ucs-2be-keyword))))

	(awhen (dfa-process order c)
	  (return-from guess-body it))
	(when (dfa-none order)
	  (return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))


(defun guess-tw (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 big5))
	  (c nil))
      (declare (dynamic-extent order))
      (loop for i of-type fixnum from 0 below len do
	(setf c (aref buffer (the fixnum i)))

	;; special treatment of iso-2022 escape sequence
	(when (and (= (the fixnum c) (the fixnum #x1b)) 
		   (< (the fixnum i) (the fixnum (1- len))))
	  (setf c (aref buffer (the fixnum (incf i))))
	  (when (or (= (the fixnum c) (the fixnum #x24))  ; $
		    (= (the fixnum c) (the fixnum #x28))) ; (
	    (return-from guess-body (iso-2022-tw-keyword))))

	;; special treatment of BOM
	(when (and (= (the fixnum i) (the fixnum 0))
		   (= (the fixnum c) (the fixnum #xff))
		   (< (the fixnum i) (the fixnum (1- len))))
	  (setf c (aref buffer (the fixnum (1+ i))))
	  (when (= (the fixnum c) #xfe)
	    (return-from guess-body (ucs-2le-keyword))))
	(when (and (= (the fixnum i) (the fixnum 0))
		   (= (the fixnum c) (the fixnum #xfe))
		   (< (the fixnum i) (the fixnum (1- len))))
	  (setf c (aref buffer (the fixnum (1+ i))))
	  (when (= (the fixnum c) #xff)
	    (return-from guess-body (ucs-2be-keyword))))

	(awhen (dfa-process order c)
	  (return-from guess-body it))
	(when (dfa-none order)
	  (return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))


(defun guess-cn (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 gb2312 gb18030)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of iso-2022 escape sequence
	      (when (and (= (the fixnum c) (the fixnum #x1b)) 
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i))))
		      (c2 (aref buffer (the fixnum (+ i 2)))))
		  (when (and (= (the fixnum c) (the fixnum #x24))        ; $
			     (or (= (the fixnum c2) (the fixnum #x29))   ; )
				 (= (the fixnum c2) (the fixnum #x2B)))) ; +
		    (return-from guess-body (iso-2022-cn-keyword)))))

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))


(defun guess-kr (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 euck johab)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of iso-2022 escape sequence
	      (when (and (= (the fixnum c) (the fixnum #x1b)) 
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i))))
		      (c2 (aref buffer (the fixnum (+ i 2)))))
		  (when (and (= (the fixnum c) (the fixnum #x24))   ; $
			     (= (the fixnum c2) (the fixnum #x29))) ; )
		    (return-from guess-body (iso-2022-kr-keyword)))))

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))

(defun guess-ar (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 iso8859-6 cp1256)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))

(defun guess-gr (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 iso8859-7 cp1253)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))

(defun guess-ru (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 cp1251 koi8-u koi8-r cp866
			     iso8859-2 iso8859-5)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))

(defun guess-hw (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 iso8859-8 cp1255)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))

(defun guess-pl (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 cp1250 iso8859-2)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))


(defun guess-tr (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 iso8859-9 cp1254)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))


(defun guess-bl (buffer &aux (len (length buffer)))
  (block guess-body
    (let ((order (generate-order utf8 iso8859-13 cp1257)))
      (declare (dynamic-extent order))
      (loop for c of-type fixnum across buffer
	    for i of-type fixnum from 0 do

	      ;; special treatment of BOM
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xff))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xfe)
		    (return-from guess-body (ucs-2le-keyword)))))
	      (when (and (= (the fixnum i) (the fixnum 0))
			 (= (the fixnum c) (the fixnum #xfe))
			 (< (the fixnum i) (the fixnum (1- len))))
		(let ((c (aref buffer (the fixnum (1+ i)))))
		  (when (= (the fixnum c) #xff)
		    (return-from guess-body (ucs-2be-keyword)))))
	      
	      (awhen (dfa-process order c)
		(return-from guess-body it))
	      (when (dfa-none order)
		(return-from guess-body  nil)))

      (aif (dfa-top order)
	  (dfa-name it)
	  nil))))
