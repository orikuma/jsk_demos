(load "package://drc_task_common/euslisp/robot-util.l")
(load "package://drc_task_common/euslisp/util.l")
(load "package://drc_task_common/euslisp/test-drc-door-task.l")

(defun generate-door-from-name
  (door-name)
  (cond ((equal door-name :drc-box2)
         (make-drc-box2-door))
        ((equal door-name :drc-test)
         (make-drc-test-door-right))
        ((equal door-name :drc-test-mirror)
         (make-drc-test-door-left))
        ((equal door-name :drc-sagami)
         (make-drc-sagami-door))
        ((equal door-name :drc-sagami-mirror)
         (make-drc-sagami-door-mirror))
        ))

(defun set-door-environment
  (&key (door-name nil)
        (door-width 895)
        (handle-l/r :left)
        (door-knob-size (float-vector 60 110 20))
        (door-knob-pos (float-vector 0 800 845))
        (door-coords (make-coords))
        (door-coords-system :origin-from-world)
        (stand-coords nil)
        (generate-ri? t) (draw? t) (use-ri? t)
        (arm :rarm)
        (robot-name "HRP2JSKNTS"))
  ;; generate robot
  (generate-robot robot-name :generate-ri? generate-ri?)
  ;; place robot to origin ;; this should be done before attaching handle to robot
  (send *robot* :reset-pose)
  (send *robot* :fix-leg-to-coords (make-coords))
  (setq *door-arm* arm)
  ;; attach handle to robot, define special pose
  (setup-door-open :draw? nil :generate-robot? nil)
  ;; attach handle to robot
  (attach-handle-to-robot-for-door)
  ;; generate door, attach handle to door
  (cond (door-name
         (generate-door-from-name door-name)
         )
        (t
         (let* ((door-handle-pos
                 (float-vector (+ (elt door-knob-pos 0) (* -0.8 (elt door-knob-size 0)))
                               (+ (elt door-knob-pos 1) (* (if (equal handle-l/r :left) -0.5 0.5) (elt door-knob-size 1)))
                               (elt door-knob-pos 2))))
           (setq *door* (instance param-door :init
                                  door-width (elt door-knob-size 0) (elt door-knob-size 1) (elt door-knob-size 2)
                                  door-knob-pos
                                  door-handle-pos
                                  :handle-l/r handle-l/r)))
         ))
  ;; place door to door-coords
  (when door-coords
    (cond ((equal door-coords-system :knob-from-body)
           (let* (door-worldcoords)
             (cond (use-ri?
                    (send *robot* :angle-vector (send *ri* :state :potentio-vector)))
                   (t
                    (send *robot* :angle-vector (get-potentio-vector-from-joint-states))))
             (send *robot* :fix-leg-to-coords (make-coords))
             ;; transfrom door-coords to become relative to world
             (setq door-worldcoords
                   (send (send (send *robot* :body_lk) :copy-worldcoords) :transform door-coords :local))
             ;; transfrom door-coords because the knob coords direction of eus model and recognitin result is different
             (setq door-worldcoords
                   (send (send door-worldcoords :rotate (deg2rad 90) :y) :rotate (deg2rad 180) :z))
             ;; fix door handle coords to become horizontal
             ;; :new-x => :new-yと:old-zと垂直
             ;; :new-y => #f(0 0 1)
             ;; :new-z => :new-x, :new-yと垂直
             (let* ((y-vec (float-vector 0 0 1))
                    (x-vec (v* y-vec (send door-worldcoords :rotate-vector (float-vector 0 0 1))))
                    (z-vec (v* x-vec y-vec)))
               (setq door-worldcoords
                     (make-coords :pos (send door-worldcoords :pos) :rot (transpose (matrix x-vec y-vec z-vec)))))
             (send *door* :move-coords door-worldcoords (send *door* :handle :knob-handle))
             ))
          (t ;; (equal door-coords-system :origin-from-world)
           (send *door* :newcoords door-coords)
           ))
    )
  ;; set robot stand-coords
  (setq *door-stand-coords* (if stand-coords stand-coords (make-coords)))
  (send *robot* :fix-leg-to-coords *door-stand-coords*)
  ;; draw
  (setq *ground* (make-cube 1000 1000 1))
  (when (or draw? (boundp '*irtviewer*))
    (objects (list *robot* *door* *ground*)))
  (when draw?
    (send *irtviewer* :draw-objects)
    (send *irtviewer* :change-background (float-vector 1 1 1))
    )
  )

(defun attach-handle-to-robot-for-door
  ()
  (let* (larm-translate-offset
         rarm-translate-offset
         larm-z-rotate-offset
         rarm-z-rotate-offset)
    ;; handle for door edge
    (cond ((or (equal *robot-name* "JAXON") (equal *robot-name* "STARO"))
           (setq larm-translate-offset (float-vector 40 40 0))
           (setq rarm-translate-offset (float-vector 40 -40 0))
           (setq larm-z-rotate-offset (deg2rad 90))
           (setq rarm-z-rotate-offset (deg2rad -90))
           )
          (t ;; (or (equal *robot-name* "HRP2JSKNT") (equal *robot-name* "HRP2JSKNTS"))
           (setq larm-translate-offset (float-vector 50 25 0))
           (setq rarm-translate-offset (float-vector 50 -25 0))
           (setq larm-z-rotate-offset 0)
           (setq rarm-z-rotate-offset 0)))
    (send *robot* :put :larm-door-coords
          (make-cascoords
           :coords (send (send (send (send *robot* :larm :end-coords) :copy-worldcoords) :translate larm-translate-offset :local) :rotate larm-z-rotate-offset :z :local)
           :parent (send (send *robot* :larm :end-coords) :parent)))
    (send *robot* :put :rarm-door-coords
          (make-cascoords
           :coords (send (send (send (send (send *robot* :rarm :end-coords) :copy-worldcoords) :translate rarm-translate-offset :local) :rotate rarm-z-rotate-offset :z :local) :rotate pi :x :local)
           :parent (send (send *robot* :rarm :end-coords) :parent)))

    )
  )

(defun reset-door-joint
  ()
  (send (send *door* :joint :door-hinge-joint) :joint-angle 0)
  (send (send *door* :joint :door-knob-joint) :joint-angle 0)
  )

(defun set-robot-initial-pose-for-door
  (&key (arm *door-arm*)
        (initial-waist-y (if (equal arm :larm) -20 20)))
  (send *robot* :reset-manip-pose)
  (send *robot* :torso :waist-y :joint-angle initial-waist-y)
  (send *robot* :fix-leg-to-coords (make-coords))
  (send *robot* arm :move-end-rot (case arm (:larm 90) (t -90)) :x)
  (send *robot* arm :move-end-rot (case arm (:larm 30) (t -30)) :z)
  (send *robot* arm :move-end-pos (float-vector 25 0 50) :world)
  (case arm
    (:larm (send *robot* :rarm :angle-vector *rarm-avoid-pose*))
    (:rarm (send *robot* :larm :angle-vector *larm-avoid-pose*)))
  ;;(send (send *robot* :hand arm) :angle-vector *door-grasp-preshape-pose*)
  )

(defun fullbody-inverse-kinematics-for-door
  (tc mt ll &key (draw? nil))
  (cond ((equal *robot-name* "JAXON")
         (fullbody-inverse-kinematics-for-door-for-jaxon tc mt ll :draw? draw?))
        ((equal *robot-name* "STARO")
         (fullbody-inverse-kinematics-for-door-for-staro tc mt ll :draw? draw?))
        (t ;; (or (equal *robot-name* "HRP2JSKNT") (equal *robot-name* "HRP2JSKNTS"))
         (fullbody-inverse-kinematics-for-door-for-hrp2 tc mt ll :draw? draw?))
        ))

(defun fullbody-inverse-kinematics-for-door-for-hrp2
  (tc mt ll &key (draw? nil))
  (send *robot*
        :fullbody-inverse-kinematics tc
        :move-target mt :link-list ll
        :root-link-virtual-joint-weight (float-vector 0.1 0.1 0.1 0.1 0.5 0.5)
        :target-centroid-pos (apply #'midpoint 0.5 (send *robot* :legs :end-coords :worldpos))
        :translation-axis (list t t t)
        :rotation-axis (list t t t)
        :warnp (if draw? t nil)
        :additional-weight-list
        (list (list (send *robot* :rleg :toe-p :child-link) 0)
              (list (send *robot* :lleg :toe-p :child-link) 0))
        :max (float-vector  500  500  0  20  20  10)
        :min (float-vector  -500  -500  -200  -20  -20  -10)
        :stop 40
        :centroid-thre 15
        :debug-view (if draw? :no-message nil)
        ))

(defun fullbody-inverse-kinematics-for-door-for-jaxon
  (tc mt ll &key (draw? nil))
  (let (ret)
    (setq ret
          (send *robot*
                :fullbody-inverse-kinematics tc
                :move-target mt :link-list ll
                :target-centroid-pos (apply #'midpoint 0.5 (send *robot* :legs :end-coords :worldpos))
                :translation-axis (list t t t)
                :rotation-axis (list t t t)
                :warnp (if draw? t nil)
                :root-link-virtual-joint-weight (float-vector 0.15 0.15 0.01 0.15 0.5 0.5)
                :additional-weight-list
                (list (list (send *robot* :torso :waist-r :child-link) 0.1)
                      (list (send *robot* :torso :waist-y :child-link) 0.1)
                      (list (send *robot* :torso :waist-p :child-link) 0.1))
                :max (float-vector  500  200  25  10  20  10)
                :min (float-vector  -500  -200  -200  -10  -20  -10)
                :stop 50
                :centroid-thre 15
                :debug-view (if draw? :no-message nil)
                :avoid-collision-distance 100
                :avoid-collision-null-gain 5.0
                :avoid-collision-joint-gain 0.8
                :collision-avoidance-link-pair
                (list (list (elt (send *robot* *door-arm* :links) 2) (send *robot* :link "CHEST_LINK2")))
                ))
    (when (and ret (send *robot* :self-collision-check)) (setq ret nil))
    ret)
  )

(defun fullbody-inverse-kinematics-for-door-for-staro
  (tc mt ll &key (draw? nil))
  (let (ret)
    (setq ret
          (send *robot*
                :fullbody-inverse-kinematics tc
                :move-target mt :link-list ll
                :target-centroid-pos (apply #'midpoint 0.5 (send *robot* :legs :end-coords :worldpos))
                :translation-axis (list t t t)
                :rotation-axis (list t t t)
                :warnp (if draw? t nil)
                :root-link-virtual-joint-weight #f(0.1 0.1 0.1 0.1 0.5 0.5)
                :additional-weight-list
                (list (list (send *robot* :torso :waist-y :child-link) 0)
                      (list (send *robot* :torso :waist-p :child-link) 0))
                :max (float-vector  500  200  25  10  20  10)
                :min (float-vector  -500  -200  -200  -10  -20  -10)
                :stop 50
                :debug-view (if draw? :no-message nil)
                :avoid-collision-distance 100
                :avoid-collision-null-gain 5.0
                :avoid-collision-joint-gain 3.0
                :collision-avoidance-link-pair
                (list (list (caddr (send *robot* :lleg :links))
                            (car (last (send *robot* :larm :links)))))
                ))
    (when (and ret (send *robot* :self-collision-check)) (setq ret nil))
    ret)
  )

(defun generate-door-motion
  (&key (draw? nil) (push/pull :push) (try-all-ik? nil))
  ;; reset door joint
  (reset-door-joint)
  (set-robot-initial-pose-for-door) ;; fix-leg-to-coords is called
  (let* ((ik-results nil)
         (ik-ret nil)
         (trans-list ;; list of eef-xyz-pos, eef-z-angle, hinge-angle, knob-angle
          (cond 
           ((equal push/pull :push)
            (list (list (float-vector -100 200 150) 0 0 0)
                  (list (float-vector 0 50 50) 0 0 0)
                  (list (float-vector 0 -25 -50) 0 0 0)
                  (list (float-vector 0 -25 -50) 0 0 -25) ;; start grasp before this
                  (list (float-vector 0 -25 -50) 0 0 -50)
                  (list (float-vector 0 -25 -50) 0 10 -50)
                  (list (float-vector 0 -25 -50) 0 15 -50)
                  (list (float-vector 0 -25 -50) 0 15 -25)
                  (list (float-vector 0 -25 -50) 0 15 0)
                  (list (float-vector 0 50 50) 0 15 0) ;; stop grasp before this
                  (list (float-vector 0 100 50) 0 15 0)
                  (list (float-vector -100 100 50) 0 15 0)
                  ))
           ((equal push/pull :pull)
            (list (list (float-vector -100 200 150) 0 0 0)
                  (list (float-vector 0 50 50) 0 0 0)
                  (list (float-vector 0 -25 -50) 0 0 0)
                  (list (float-vector 0 -25 -50) 0 0 -25) ;; start grasp before this
                  (list (float-vector 0 -25 -50) 0 0 -50)
                  (list (float-vector 0 -25 -50) 0 -10 -50)
                  (list (float-vector 0 -25 -50) 0 -20 -50)
                  (list (float-vector 0 -25 -50) 0 -20 -25)
                  (list (float-vector 0 -25 -50) 0 -20 0)
                  (list (float-vector 0 50 50) 0 -20 0) ;; stop grasp before this
                  (list (float-vector 0 100 50) 0 -20 0)
                  (list (float-vector -100 100 50) 0 -20 0)
                  ))
           ))
         )
    (dotimes (i (length trans-list))
      (send *robot* :reset-manip-pose)
      (send *robot* :fix-leg-to-coords *door-stand-coords*) ;; this should be called after (set-robot-initial-pose-for-door)
      (let* ((trans (elt trans-list i))
             (trans-handle-pos
              (float-vector (elt (elt trans 0) 0) (elt (elt trans 0) 1) (if (equal (send *door* :get :handle-l/r) :left) (elt (elt trans 0) 2) (- (elt (elt trans 0) 2)))))
             (tc
              (list (send (send
                           (send (send *door* :handle :knob-handle) :copy-worldcoords)
                           :translate trans-handle-pos :local) :rotate (deg2rad (elt trans 1)) :z :local)
                    (send *robot* :rleg :end-coords :copy-worldcoords)
                    (send *robot* :lleg :end-coords :copy-worldcoords))))
        (send (send *door* :joint :door-hinge-joint) :joint-angle (elt trans 2))
        (send (send *door* :joint :door-knob-joint) :joint-angle (elt trans 3))
        (with-move-target-link-list
         (mt ll *robot* (list *door-arm* :rleg :lleg))
         (setf (elt mt 0) (send *robot* :get (read-from-string (format nil "~a-door-coords" *door-arm*))))
         (setq ik-ret (fullbody-inverse-kinematics-for-door tc mt ll :draw? draw?))
         (when ik-ret
           (setq ik-ret (send *robot* :look-at-target (send *door* :handle :knob-handle))))
         (push-back (list i (not (null ik-ret)) ik-ret) ik-results)
         (when (and (not try-all-ik?) (not ik-ret))
           (return-from nil nil))
         ))
      )
    (setq *door-ik-results* ik-results)
    )
  )

(defun get-door-motion
  (&key (draw? nil) (push/pull :push))
  (generate-door-motion :draw? draw? :push/pull push/pull)
  (setq *door-motion* nil)
  (when (every #'eval (mapcar #'(lambda (x) (elt x 1)) *door-ik-results*))
    (setq *door-motion* (mapcar #'(lambda (x) (elt x 2)) *door-ik-results*)))
  )

(defun get-door-stand-coords ;; relative to door
  (&key (handle-l/r :left) (push/pull :push))
  (cond ((or (equal *robot-name* "JAXON") (equal *robot-name* "STARO"))
         (cond ((equal handle-l/r :left)
                (cond ((equal push/pull :push)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -600 450 0) :rpy (list (deg2rad -80) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -600 450 0) :rpy (list (deg2rad -80) 0 0))
                              )))
                      ((equal push/pull :pull)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -800 450 0) :rpy (list (deg2rad 80) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -800 450 0) :rpy (list (deg2rad 80) 0 0))
                              )))))
               ((equal handle-l/r :right)
                (cond ((equal push/pull :push)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -600 -450 0) :rpy (list (deg2rad 80) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -600 -450 0) :rpy (list (deg2rad 80) 0 0))
                              )))
                      ((equal push/pull :pull)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -800 -450 0) :rpy (list (deg2rad -80) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -800 -450 0) :rpy (list (deg2rad -80) 0 0))
                              )))))
               ))
        (t ;; (or (equal *robot-name* "HRP2JSKNT") (equal *robot-name* "HRP2JSKNTS"))
         (cond ((equal handle-l/r :left)
                (cond ((equal push/pull :push)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -625 425 0) :rpy (list (deg2rad -20) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -625 425 0) :rpy (list (deg2rad -20) 0 0))
                              )))
                      ((equal push/pull :pull)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -600 350 0) :rpy (list (deg2rad 20) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -600 350 0) :rpy (list (deg2rad 20) 0 0))
                              )))))
               ((equal handle-l/r :right)
                (cond ((equal push/pull :push)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -625 -425 0) :rpy (list (deg2rad 20) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -625 -425 0) :rpy (list (deg2rad 20) 0 0))
                              )))
                      ((equal push/pull :pull)
                       (cond ((equal *door-arm* :larm)
                              (make-coords :pos (float-vector -600 -350 0) :rpy (list (deg2rad -20) 0 0))
                              )
                             ((equal *door-arm* :rarm)
                              (make-coords :pos (float-vector -600 -350 0) :rpy (list (deg2rad -20) 0 0))
                              )))))
               )))
  )

(defun move-robot-with-stand-coords-for-door
  (stand-coords)
  (let* ((x-vec (send (send (send *door* :worldcoords) :copy-worldcoords) :rotate-vector (float-vector 1 0 0)))
         (z-vec (float-vector 0 0 1))
         (y-vec (v* z-vec x-vec))
         (door-coords-stand-rot (make-coords :pos (send (send *door* :worldcoords) :worldpos) :rot (transpose (matrix x-vec y-vec z-vec))))
         (tmp-stand-coords (send (send door-coords-stand-rot :copy-worldcoords) :transform stand-coords :local))
         (stand-pos (send tmp-stand-coords :worldpos))
         (stand-rpy (elt (send tmp-stand-coords :rpy-angle) 0))
         )
    (setq *door-stand-coords* (make-coords :pos (float-vector (elt stand-pos 0) (elt stand-pos 1) 0) :rpy (list (elt stand-rpy 0) 0 0)))
    )
  )

(defun get-door-motion-full
  (&key (door-name nil)
        (door-width 895)
        (handle-l/r :left)
        (door-knob-size (float-vector 60 110 20))
        (door-knob-pos (float-vector 0 800 845))
        (door-coords (make-coords))
        (door-coords-system :knob-from-body)
        (arm :rarm) (push/pull :push)
        (stand-coords nil)
        (overwrite-stand-coords? nil) (overwrite-arm-side? nil)
        (draw? nil) (draw-environment? nil) (use-ri? t)
        (robot-name "HRP2JSKNTS")
        )
  (set-door-environment
   :door-name door-name :door-width door-width :handle-l/r handle-l/r
   :door-knob-size door-knob-size :door-knob-pos door-knob-pos
   :door-coords door-coords :door-coords-system door-coords-system
   :stand-coords stand-coords :arm arm :draw? (or draw? draw-environment?)
   :use-ri? use-ri? :generate-ri? use-ri? :robot-name robot-name)
  (get-door-motion :push/pull push/pull :draw? draw?)
  ;; change arm
  (when (and overwrite-arm-side? (not *door-motion*))
    (setq *door-arm* (get-opposite-arm *door-arm*))
    (ros::ros-warn "change arm side to ~a for door motion. (stand position is ~a.) ~%" *door-arm* *door-stand-coords*)
    (get-door-motion :push/pull push/pull :draw? draw?)
    )
  ;; revert arm, change stand position
  (when (and overwrite-stand-coords? (not *door-motion*))
    (when overwrite-arm-side? (setq *door-arm* (get-opposite-arm *door-arm*)))
    (move-robot-with-stand-coords-for-door (get-door-stand-coords :handle-l/r (send *door* :get :handle-l/r) :push/pull push/pull))
    (ros::ros-warn "change stand position to ~a for door motion. (arm side is ~a.)~%" *door-stand-coords* *door-arm*)
    (get-door-motion :push/pull push/pull :draw? draw?)
    )
  ;; change arm, change stand position
  (when (and overwrite-arm-side? overwrite-stand-coords? (not *door-motion*))
    (when overwrite-arm-side? (setq *door-arm* (get-opposite-arm *door-arm*)))
    (move-robot-with-stand-coords-for-door (get-door-stand-coords :handle-l/r (send *door* :get :handle-l/r) :push/pull push/pull))
    (ros::ros-warn "change arm side to ~a and stand position to ~a for door motion.~%" *door-arm* *door-stand-coords*)
    (get-door-motion :push/pull push/pull :draw? draw?)
    )
  *door-motion*)

(defun send-door-motion
  (&key (door-name nil)
        (door-width 895)
        (handle-l/r :left)
        (door-knob-size (float-vector 60 110 20))
        (door-knob-pos (float-vector 0 800 845))
        (door-coords (make-coords :pos (float-vector 650 -450 0) :rpy (list (deg2rad 15) 0 0)))
        (push/pull :push)
        (arm :rarm) (overwrite-arm-side? nil)
        (stand-coords nil) (overwrite-stand-coords? nil)
        (real? t) (test-mode? nil) (av-list nil)
        )
  (let* ((door-motion-av-list
          (if av-list
              av-list
            (get-door-motion-full
             :door-name door-name :door-width door-width :handle-l/r handle-l/r :push/pull push/pull
             :door-knob-size door-knob-size :door-knob-pos door-knob-pos
             :door-coords door-coords :door-coords-system :knob-from-body :arm arm :overwrite-arm-side? overwrite-arm-side?
             :stand-coords stand-coords :overwrite-stand-coords? overwrite-stand-coords?
             :draw-environment? test-mode?))))
    )
  ;; reset-manip-pose
  (hand-start-grasp :real? real? :type :door-grasp-preshape)
  (send *robot* :reset-manip-pose)
  (unless (check-angle-vector-distance)
    (when real? (model2real :time 3000)))
  (when real?
    (cond ((or (equal *robot-name* "JAXON") (equal *robot-name* "STARO"))
           (send *ri* :start-impedance :arms :moment-gain (float-vector 0 0 0) :k-p 300 :d-p 300))
          (t ;; (or (equal *robot-name* "HRP2JSKNT") (equal *robot-name* "HRP2JSKNTS"))
           (send *ri* :start-impedance :arms :k-p 200 :d-p 180 :m-p 5 :m-r 1 :d-r 15 :k-r 20)
           )))
  ;; walk
  (when *door-stand-coords*
    (let* ((pos (scale 0.001 (send *door-stand-coords* :worldpos)))
           (rpy (mapcar #'rad2deg (car (send *door-stand-coords* :rpy-angle))))
           (pos-thre 0.01)
           (rpy-thre 1)
           )
      (when (or (> (abs (elt pos 0)) pos-thre) (> (abs (elt pos 1)) pos-thre) (> (abs (elt rpy 0)) rpy-thre))
        (ros::ros-warn "go-pos to ~a ~a ~a for door~%" (elt pos 0) (elt pos 1) (elt rpy 0))
        (when real? (send *ri* :go-pos (elt pos 0) (elt pos 1) (elt rpy 0)))
        )
      ))
  (dotimes (i (length *door-motion*))
    (cond ((= i 3)
           (hand-start-grasp :real? real? :type :door-grasp))
          ((= i 9)
           (hand-start-grasp :real? real? :type :door-grasp-preshape))
          )
    (send *ri* :state)
    (warning-message 1 "(send *robot* :angle-vector ~a) ;; reference-vector ~a~%" (send *ri* :reference-vector) i)
    (warning-message 1 "(send *robot* :angle-vector ~a) ;; potentio-vector ~a~%" (send *ri* :potentio-vector) i)
    (send *robot* :angle-vector (elt *door-motion* i))
    (when real? (model2real :time 3000))
    )
  (send *robot* :reset-manip-pose)
  (when real? (model2real :time 5000))
  )

(defun publish-door-motion
  (&key (door-name nil)
        (door-width 895)
        (handle-l/r :left)
        (door-knob-size (float-vector 60 110 20))
        (door-knob-pos (float-vector 0 800 845))
        (door-coords (make-coords :pos (float-vector 650 -450 0) :rpy (list (deg2rad 15) 0 0)))
        (push/pull :push)
        (arm :rarm) (overwrite-arm-side? nil)
        (stand-coords nil) (overwrite-stand-coords? nil)
        (step-time 200) (update? t) (test-mode? nil))
  (when update?
    (get-door-motion-full
     :door-name door-name :door-width door-width :handle-l/r handle-l/r :push/pull push/pull
     :door-knob-size door-knob-size :door-knob-pos door-knob-pos
     :door-coords door-coords :door-coords-system :knob-from-body :arm arm :overwrite-arm-side? overwrite-arm-side?
     :stand-coords stand-coords :overwrite-stand-coords? overwrite-stand-coords?
     :use-ri? (if test-mode? t nil)))
  (ros::ros-info "door-stand-coords: ~a~%" *door-stand-coords*)
  (ros::ros-info "door-ik-results: ~a~%" *door-ik-results*)
  (when *door-stand-coords*
    (move-robot-model *door-stand-coords* "ground"))
  (publish-motion-joint-states *door-motion* :step-time step-time)
  )
