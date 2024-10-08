module LBL
    use Constants
    use ShapeFuncInterface
    use Atmosphere
    use Mesh
    use IO
    use Spectroscopy
    use MolarMasses
    use Shapes
    use LineGridCalc
    implicit none
    integer, parameter :: hitranFileUnit = 7777
contains

    subroutine modernLBL(LINBEG, capWV)
        
        ! integer :: molTypeArg
        integer :: LINBEG ! integer line label used for locating record in direct access file
        integer :: I ! loop variable for accessing the record in direct access file
        ! integer :: loopLevel
        ! integer, save :: currentLevel
        integer :: ios2

        ! this variable serves as a cap in the loop to stop increasing the lineIdx
        ! it is the value as when there is the next step over the DeltaWV, hitran reading will from the correct record number
        ! the definition and the value assignment is in K_HTRAN module
        real(kind=DP) :: capWV

        real, parameter :: BOUNDL = 10. ! some boundary parameter
        real, parameter :: BOUNDD = 0.01 ! likely some boundary value related to Doppler broadening, given its small value

        ! real, save :: unitlessT ! unitless temperature (refTemperature/T)

        ! real :: lineIntensity ! SLL ! temperature and pressure dependent line intensity
        
        ! real, save :: pSelf ! self-broadening pressure component
        ! real, save :: pForeign ! foreign gas broadening component
        
        ! Appears in the denominator of the Lorentzian line profile L(\nu)
        real(kind=DP) :: shiftedLineWV ! VI ! shifted line position under the current atmospheric pressure

        ! integer :: isotopeNum ! N_MOLIS ! for categorizing isotopolouges in more broader group
        
        ! real :: alphaT ! ADD ! The half-width at half-maximum (HWHM) of the Doppler-broadened component

        ! it characterizes the relative contributions of Lorentzian and Doppler broadening to the overall shape of the spectral line
        real(kind=DP) :: shapePrevailFactor ! ALAD ! ratio of is the ratio of the Lorentz HWHM (AL) to the Doppler width (ADD).

        ! -------- Line-by-line loop (iteration over records in HITRAN file) ------ !

        I = LINBEG - 1
        ios2 = 0
        do while (.not. is_iostat_end(ios))
            I = I + 1
            read(hitranFileUnit, rec=I, iostat=ios2) lineWV, refLineIntensity, gammaForeign, gammaSelf, lineLowerState, foreignTempCoeff, &
                                jointMolIso, deltaForeign

            if (ios2 > 0) then
                print *, 'ERROR: when reading file with spectral data.'
                stop 9
            end if

            if  (lineWV >= extEndDeltaWV) exit

            if  (lineWV <= capWV) LINBEG = I

            isotopeNum = jointMolIso/100

            molarMass = WISO(isotopeNum)

            ! AL
            LorHWHM = lorentzHWHM(pressure, includeGammaSelf=.true., partialPressureParameter=pSelf, & 
                                includeTemperature=.true., temperatureParameter=temperature)
    
            ! ADD
            DopHWHM = dopplerHWHM(lineWV, temperature, molarMass)

            shapePrevailFactor = LorHWHM / (DopHWHM/sqln2) ! <----- ratio to see which effect (Doppler or Lorentz prevails)

            shiftedLineWV = shiftedLinePosition(lineWV, pressure)
            
            if (shapePrevailFactor > BOUNDL) then
                if (shiftedLineWV < startDeltaWV) then
                    shapeFuncPtr => chiCorrectedLorentz
                    call leftLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr) 
                else 
                    if (shiftedLineWV >= endDeltaWV) then
                        shapeFuncPtr => chiCorrectedLorentz
                        call rightLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                    else 
                        shapeFuncPtr => chiCorrectedLorentz
                        call centerLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                    end if
                end if
            else
                if (shapePrevailFactor > BOUNDD) then
                    if (shiftedLineWV < startDeltaWV) then
                        shapeFuncPtr => voigt
                        call leftLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                    else
                        if (shiftedLineWV >= endDeltaWV) then
                            shapeFuncPtr => voigt
                            call rightLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                        else 
                            shapeFuncPtr => voigt
                            call centerLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                        end if
                    end if
                else 
                    if (shiftedLineWV < startDeltaWV ) then
                        shapeFuncPtr => doppler
                        call leftLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                    else 
                        if (shiftedLineWV >= endDeltaWV) then
                            shapeFuncPtr => doppler
                            call rightLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                        else 
                            shapeFuncPtr => doppler
                            call centerLBL(startDeltaWV, shiftedLineWV, shapeFuncPtr)
                        end if
                    end if
                end if
            end if 
        end do
        ! -------- End of line-by-line loop (iteration over records in HITRAN file) --!
    end subroutine modernLBL
end module LBL
