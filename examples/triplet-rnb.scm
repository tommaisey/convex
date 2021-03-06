;; A groovy little number...

(pattern p1
  (part
    (part ;; Keys
      (in: :scd (sbdv 2 [[I III] I VI ~])
           (to: :octave (sbdv [0 1 (? [1 0]) 0]))
           (rp: (sbdv 4 [! (chord triad) (chord 7th) (chord 9th)])))

      (cp: (to: :octave -1)
           (to+ :beat 1/12))

      (in: :scd (sbdv [I III IV])
           (to: :octave 1))

      (in: :scd (sbdv 2 [I [I III] IV II])
           (to: :octave -1))

      (to: :scale dorian
           :inst "swirly-keys"
           :bus1-amt 0.03
           :attack 0.002
           :sustain 0
           :release (sbdv [1 0.5 0.5 2]))

      (to* :release 0.3)

      (part ;; Drums
        (in: :sample (sbdv 1/3 [~ hh × ×])
             (to: :sample-idx 12
                  :amp 0.1
                  :pan (? 0.1 0.7)))

        (in! (sbdv 2 [(? 1 3) 1 [1 1] 1])
             (to: :sample bd
                  :sample-idx 80))

        (in: :sample (sbdv 1 [~ sn ~ sn])
             (to: :amp 0.2))
        (mv+ (sbdv 1/4 (? 0.0 0.011)))
        (to: :speed (? 0.975 1.0)
             :bus1-amt 0.02)))))
