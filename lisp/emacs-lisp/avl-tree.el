;;; avl-tree.el --- balanced binary trees, AVL-trees

;; Copyright (C) 1995, 2007 Free Software Foundation, Inc.

;; Author: Per Cederqvist <ceder@lysator.liu.se>
;;	Inge Wallin <inge@lysator.liu.se>
;;	Thomas Bellman <bellman@lysator.liu.se>
;; Maintainer: FSF
;; Created: 10 May 1991
;; Keywords: extensions, data structures

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This file combines elib-node.el and avltree.el from Elib.
;;
;; * Comments from elib-node.el
;; A node is implemented as an array with three elements, using
;; (elt node 0) as the left pointer
;; (elt node 1) as the right pointer
;; (elt node 2) as the data
;;
;; Some types of trees, e.g. AVL trees, need bigger nodes, but
;; as long as the first three parts are the left pointer, the
;; right pointer and the data field, these macros can be used.
;;
;; * Comments from avltree.el
;; An AVL tree is a nearly-perfect balanced binary tree.  A tree
;; consists of two cons cells, the first one holding the tag
;; 'AVL-TREE in the car cell, and the second one having the tree
;; in the car and the compare function in the cdr cell.  The tree has
;; a dummy node as its root with the real tree in the left pointer.
;;
;; Each node of the tree consists of one data element, one left
;; sub-tree and one right sub-tree.  Each node also has a balance
;; count, which is the difference in depth of the left and right
;; sub-trees.

;;; Code:

(defmacro elib-node-left (node)
  ;; Return the left pointer of NODE.
  `(aref ,node 0))

(defmacro elib-node-right (node)
  ;; Return the right pointer of NODE.
  `(aref ,node 1))

(defmacro elib-node-data (node)
  ;; Return the data of NODE.
  `(aref ,node 2))

(defmacro elib-node-set-left (node newleft)
  ;; Set the left pointer of NODE to NEWLEFT.
  `(aset ,node 0 ,newleft))

(defmacro elib-node-set-right (node newright)
  ;; Set the right pointer of NODE to NEWRIGHT.
  `(aset ,node 1 ,newright))

(defmacro elib-node-set-data (node newdata)
  ;; Set the data of NODE to NEWDATA.
  `(aset ,node 2 ,newdata))

(defmacro elib-node-branch (node branch)
  ;; Get value of a branch of a node.
  ;;
  ;; NODE is the node, and BRANCH is the branch.
  ;; 0 for left pointer, 1 for right pointer and 2 for the data."
  `(aref ,node ,branch))

(defmacro elib-node-set-branch (node branch newval)
  ;; Set value of a branch of a node.
  ;;
  ;; NODE is the node, and BRANCH is the branch.
  ;; 0 for left pointer, 1 for the right pointer and 2 for the data.
  ;; NEWVAL is new value of the branch."
  `(aset ,node ,branch ,newval))

;;; ================================================================
;;;        Functions and macros handling an AVL tree node.

(defmacro avl-tree-node-create (left right data balance)
  ;; Create and return an avl-tree node.
  `(vector ,left ,right ,data ,balance))

(defmacro avl-tree-node-balance (node)
  ;; Return the balance field of a node.
  `(aref ,node 3))

(defmacro avl-tree-node-set-balance (node newbal)
  ;; Set the balance field of a node.
  `(aset ,node 3 ,newbal))


;;; ================================================================
;;;       Internal functions for use in the AVL tree package

(defmacro avl-tree-root (tree)
  ;; Return the root node for an avl-tree.  INTERNAL USE ONLY.
  `(elib-node-left (car (cdr ,tree))))

(defmacro avl-tree-dummyroot (tree)
  ;; Return the dummy node of an avl-tree.  INTERNAL USE ONLY.
  `(car (cdr ,tree)))

(defmacro avl-tree-cmpfun (tree)
  ;; Return the compare function of AVL tree TREE.  INTERNAL USE ONLY.
  `(cdr (cdr ,tree)))

;; ----------------------------------------------------------------
;;                          Deleting data

(defun avl-tree-del-balance1 (node branch)
  ;; Rebalance a tree and return t if the height of the tree has shrunk.
  (let* ((br (elib-node-branch node branch))
         p1
         b1
         p2
         b2
         result)
    (cond
     ((< (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br 0)
      t)

     ((= (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br +1)
      nil)

     (t
      ;; Rebalance.
      (setq p1 (elib-node-right br)
            b1 (avl-tree-node-balance p1))
      (if (>= b1 0)
          ;; Single RR rotation.
          (progn
            (elib-node-set-right br (elib-node-left p1))
            (elib-node-set-left p1 br)
            (if (= 0 b1)
                (progn
                  (avl-tree-node-set-balance br +1)
                  (avl-tree-node-set-balance p1 -1)
                  (setq result nil))
              (avl-tree-node-set-balance br 0)
              (avl-tree-node-set-balance p1 0)
              (setq result t))
            (elib-node-set-branch node branch p1)
            result)

        ;; Double RL rotation.
        (setq p2 (elib-node-left p1)
              b2 (avl-tree-node-balance p2))
        (elib-node-set-left p1 (elib-node-right p2))
        (elib-node-set-right p2 p1)
        (elib-node-set-right br (elib-node-left p2))
        (elib-node-set-left p2 br)
        (if (> b2 0)
            (avl-tree-node-set-balance br -1)
          (avl-tree-node-set-balance br 0))
        (if (< b2 0)
            (avl-tree-node-set-balance p1 +1)
          (avl-tree-node-set-balance p1 0))
        (elib-node-set-branch node branch p2)
        (avl-tree-node-set-balance p2 0)
        t)))))

(defun avl-tree-del-balance2 (node branch)
  (let* ((br (elib-node-branch node branch))
         p1
         b1
         p2
         b2
         result)
    (cond
     ((> (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br 0)
      t)

     ((= (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br -1)
      nil)

     (t
      ;; Rebalance.
      (setq p1 (elib-node-left br)
            b1 (avl-tree-node-balance p1))
      (if (<= b1 0)
          ;; Single LL rotation.
          (progn
            (elib-node-set-left br (elib-node-right p1))
            (elib-node-set-right p1 br)
            (if (= 0 b1)
                (progn
                  (avl-tree-node-set-balance br -1)
                  (avl-tree-node-set-balance p1 +1)
                  (setq result nil))
              (avl-tree-node-set-balance br 0)
              (avl-tree-node-set-balance p1 0)
              (setq result t))
            (elib-node-set-branch node branch p1)
            result)

        ;; Double LR rotation.
        (setq p2 (elib-node-right p1)
              b2 (avl-tree-node-balance p2))
        (elib-node-set-right p1 (elib-node-left p2))
        (elib-node-set-left p2 p1)
        (elib-node-set-left br (elib-node-right p2))
        (elib-node-set-right p2 br)
        (if (< b2 0)
            (avl-tree-node-set-balance br +1)
          (avl-tree-node-set-balance br 0))
        (if (> b2 0)
            (avl-tree-node-set-balance p1 -1)
          (avl-tree-node-set-balance p1 0))
        (elib-node-set-branch node branch p2)
        (avl-tree-node-set-balance p2 0)
        t)))))

(defun avl-tree-do-del-internal (node branch q)

  (let* ((br (elib-node-branch node branch)))
    (if (elib-node-right br)
        (if (avl-tree-do-del-internal br +1 q)
            (avl-tree-del-balance2 node branch))
      (elib-node-set-data q (elib-node-data br))
      (elib-node-set-branch node branch
                            (elib-node-left br))
      t)))

(defun avl-tree-do-delete (cmpfun root branch data)
  ;; Return t if the height of the tree has shrunk.
  (let* ((br (elib-node-branch root branch)))
    (cond
     ((null br)
      nil)

     ((funcall cmpfun data (elib-node-data br))
      (if (avl-tree-do-delete cmpfun br 0 data)
          (avl-tree-del-balance1 root branch)))

     ((funcall cmpfun (elib-node-data br) data)
      (if (avl-tree-do-delete cmpfun br 1 data)
          (avl-tree-del-balance2 root branch)))

     (t
      ;; Found it.  Let's delete it.
      (cond
       ((null (elib-node-right br))
        (elib-node-set-branch root branch (elib-node-left br))
        t)

       ((null (elib-node-left br))
        (elib-node-set-branch root branch (elib-node-right br))
        t)

       (t
        (if (avl-tree-do-del-internal br 0 br)
            (avl-tree-del-balance1 root branch))))))))

;; ----------------------------------------------------------------
;;                           Entering data

(defun avl-tree-enter-balance1 (node branch)
  ;; Rebalance a tree and return t if the height of the tree has grown.
  (let* ((br (elib-node-branch node branch))
         p1
         p2
         b2
         result)
    (cond
     ((< (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br 0)
      nil)

     ((= (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br +1)
      t)

     (t
      ;; Tree has grown => Rebalance.
      (setq p1 (elib-node-right br))
      (if (> (avl-tree-node-balance p1) 0)
          ;; Single RR rotation.
          (progn
            (elib-node-set-right br (elib-node-left p1))
            (elib-node-set-left p1 br)
            (avl-tree-node-set-balance br 0)
            (elib-node-set-branch node branch p1))

        ;; Double RL rotation.
        (setq p2 (elib-node-left p1)
              b2 (avl-tree-node-balance p2))
        (elib-node-set-left p1 (elib-node-right p2))
        (elib-node-set-right p2 p1)
        (elib-node-set-right br (elib-node-left p2))
        (elib-node-set-left p2 br)
        (if (> b2 0)
            (avl-tree-node-set-balance br -1)
          (avl-tree-node-set-balance br 0))
        (if (< b2 0)
            (avl-tree-node-set-balance p1 +1)
          (avl-tree-node-set-balance p1 0))
        (elib-node-set-branch node branch p2))
      (avl-tree-node-set-balance (elib-node-branch node branch) 0)
      nil))))

(defun avl-tree-enter-balance2 (node branch)
  ;; Return t if the tree has grown.
  (let* ((br (elib-node-branch node branch))
         p1
         p2
         b2)
    (cond
     ((> (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br 0)
      nil)

     ((= (avl-tree-node-balance br) 0)
      (avl-tree-node-set-balance br -1)
      t)

     (t
      ;; Balance was -1 => Rebalance.
      (setq p1 (elib-node-left br))
      (if (< (avl-tree-node-balance p1) 0)
          ;; Single LL rotation.
          (progn
            (elib-node-set-left br (elib-node-right p1))
            (elib-node-set-right p1 br)
            (avl-tree-node-set-balance br 0)
            (elib-node-set-branch node branch p1))

        ;; Double LR rotation.
        (setq p2 (elib-node-right p1)
              b2 (avl-tree-node-balance p2))
        (elib-node-set-right p1 (elib-node-left p2))
        (elib-node-set-left p2 p1)
        (elib-node-set-left br (elib-node-right p2))
        (elib-node-set-right p2 br)
        (if (< b2 0)
            (avl-tree-node-set-balance br +1)
          (avl-tree-node-set-balance br 0))
        (if (> b2 0)
            (avl-tree-node-set-balance p1 -1)
          (avl-tree-node-set-balance p1 0))
        (elib-node-set-branch node branch p2))
      (avl-tree-node-set-balance (elib-node-branch node branch) 0)
      nil))))

(defun avl-tree-do-enter (cmpfun root branch data)
  ;; Return t if height of tree ROOT has grown.  INTERNAL USE ONLY.
  (let ((br (elib-node-branch root branch)))
    (cond
     ((null br)
      ;; Data not in tree, insert it.
      (elib-node-set-branch root branch
                            (avl-tree-node-create nil nil data 0))
      t)

     ((funcall cmpfun data (elib-node-data br))
      (and (avl-tree-do-enter cmpfun
                              br
                              0 data)
           (avl-tree-enter-balance2 root branch)))

     ((funcall cmpfun (elib-node-data br) data)
      (and (avl-tree-do-enter cmpfun
                              br
                              1 data)
           (avl-tree-enter-balance1 root branch)))

     (t
      (elib-node-set-data br data)
      nil))))

;; ----------------------------------------------------------------

(defun avl-tree-mapc (map-function root)
  ;; Apply MAP-FUNCTION to all nodes in the tree starting with ROOT.
  ;; The function is applied in-order.
  ;;
  ;; Note: MAP-FUNCTION is applied to the node and not to the data itself.
  ;; INTERNAL USE ONLY.
  (let ((node root)
        (stack nil)
        (go-left t))
    (push nil stack)
    (while node
      (if (and go-left
               (elib-node-left node))
          ;; Do the left subtree first.
          (progn
            (push node stack)
            (setq node (elib-node-left node)))
        ;; Apply the function...
        (funcall map-function node)
        ;; and do the right subtree.
        (if (elib-node-right node)
            (setq node (elib-node-right node)
                  go-left t)
          (setq node (pop stack)
                go-left nil))))))

(defun avl-tree-do-copy (root)
  ;; Copy the tree with ROOT as root.
  ;; Highly recursive. INTERNAL USE ONLY.
  (if (null root)
      nil
    (avl-tree-node-create (avl-tree-do-copy (elib-node-left root))
                          (avl-tree-do-copy (elib-node-right root))
                          (elib-node-data root)
                          (avl-tree-node-balance root))))


;;; ================================================================
;;;       The public functions which operate on AVL trees.

(defun avl-tree-create (compare-function)
  "Create an empty avl tree.
COMPARE-FUNCTION is a function which takes two arguments, A and B,
and returns non-nil if A is less than B, and nil otherwise."
  (cons 'AVL-TREE
        (cons (avl-tree-node-create nil nil nil 0)
              compare-function)))

(defun avl-tree-p (obj)
  "Return t if OBJ is an avl tree, nil otherwise."
  (eq (car-safe obj) 'AVL-TREE))

(defun avl-tree-compare-function (tree)
  "Return the comparision function for the avl tree TREE."
  (avl-tree-cmpfun tree))

(defun avl-tree-empty (tree)
  "Return t if TREE is emtpy, otherwise return nil."
  (null (avl-tree-root tree)))

(defun avl-tree-enter (tree data)
  "In the avl tree TREE insert DATA.
Return DATA."
  (avl-tree-do-enter (avl-tree-cmpfun tree)
                     (avl-tree-dummyroot tree)
                     0
                     data)
  data)

(defun avl-tree-delete (tree data)
  "From the avl tree TREE, delete DATA.
Return the element in TREE which matched DATA, nil if no element matched."
  (avl-tree-do-delete (avl-tree-cmpfun tree)
                      (avl-tree-dummyroot tree)
                      0
                      data))

(defun avl-tree-member (tree data)
  "Return the element in the avl tree TREE which matches DATA.
Matching uses the compare function previously specified in `avl-tree-create'
when TREE was created.

If there is no such element in the tree, the value is nil."
  (let ((node (avl-tree-root tree))
        (compare-function (avl-tree-cmpfun tree))
        found)
    (while (and node
                (not found))
      (cond
       ((funcall compare-function data (elib-node-data node))
        (setq node (elib-node-left node)))
       ((funcall compare-function (elib-node-data node) data)
        (setq node (elib-node-right node)))
       (t
        (setq found t))))

    (if node
        (elib-node-data node)
      nil)))

(defun avl-tree-map (__map-function__ tree)
  "Apply MAP-FUNCTION to all elements in the avl tree TREE."
  (avl-tree-mapc
   (function (lambda (node)
               (elib-node-set-data node
                                   (funcall __map-function__
                                            (elib-node-data node)))))
   (avl-tree-root tree)))

(defun avl-tree-first (tree)
  "Return the first element in TREE, or nil if TREE is empty."
  (let ((node (avl-tree-root tree)))
    (if node
        (progn
          (while (elib-node-left node)
            (setq node (elib-node-left node)))
          (elib-node-data node))
      nil)))

(defun avl-tree-last (tree)
  "Return the last element in TREE, or nil if TREE is empty."
  (let ((node (avl-tree-root tree)))
    (if node
        (progn
          (while (elib-node-right node)
            (setq node (elib-node-right node)))
          (elib-node-data node))
      nil)))

(defun avl-tree-copy (tree)
  "Return a copy of the avl tree TREE."
  (let ((new-tree (avl-tree-create
                   (avl-tree-cmpfun tree))))
    (elib-node-set-left (avl-tree-dummyroot new-tree)
                        (avl-tree-do-copy (avl-tree-root tree)))
    new-tree))

(defun avl-tree-flatten (tree)
  "Return a sorted list containing all elements of TREE."
  (nreverse
   (let ((treelist nil))
     (avl-tree-mapc (function (lambda (node)
                                (setq treelist (cons (elib-node-data node)
                                                     treelist))))
                    (avl-tree-root tree))
     treelist)))

(defun avl-tree-size (tree)
  "Return the number of elements in TREE."
  (let ((treesize 0))
    (avl-tree-mapc (function (lambda (data)
                               (setq treesize (1+ treesize))
                               data))
                   (avl-tree-root tree))
    treesize))

(defun avl-tree-clear (tree)
  "Clear the avl tree TREE."
  (elib-node-set-left (avl-tree-dummyroot tree) nil))

(provide 'avl-tree)

;; arch-tag: 47e26701-43c9-4222-bd79-739eac6357a9
;;; avl-tree.el ends here
