!*******************************************************************************
! main.f90
!*******************************************************************************
!
! Legacy code: Boris Fomin
! Rework and new features: Mikhail Razumovskii
!
! Program Description:
! This program calculates PT-TABLE (Pressure-Temperature Table) for Venus Atmosphere,
! specifically designed to handle temperatures up to 1000 K. The current version focuses
! on line-by-line spectroscopic analysis for a single gas species at a time,
! supporting H2O, CO2, or SO2. It does not incorporate continuum models.
!
! Principal Features:
! 1. 9 internal grids for detailed spectral analysis.
! 2. Adapted for high-resolution spectroscopic data from HITRAN database.
!*******************************************************************************

program main
    use Constants
    use IO
    use Atmosphere
    use Spectroscopy
    use LBL
    use Mesh
    implicit none

    ! MAIN OUTPUT FILE !
    integer, parameter :: outputUnit = 47 ! IOUT ! ** ! output file unit where spectral PT-tables will be stored for each atmospheric level
    integer :: outputRecNum ! NW ! ** ! record number in the output file

    ! CONTROL AND DEBUG FILES !
    integer, parameter :: atmControlUnit = 5555 ! NEW ! ** !

    ! Other variables !
    character(len=3) :: reducedMoleculeName ! 
    character(len=3) :: levelLabel ! unique identifier for each Zj level: ('1__','2__',...,'100',...)


    ! TODO: optimization proposition. Reduce reading operations because of highly overlaping intervals: [extStartWV1, extEndWV1] and [extStartWV2, extEndWV2]
    
    EPS = 0.0
    H0 = STEP ! STEP = 1.0
    H1 = H0/2.
    H2 = H1/2.
    H3 = H2/2.
    H4 = H3/2.
    H5 = H4/2.
    H6 = H5/2.
    H7 = H6/2. 
    H8 = H7/2. 
    H9 = H8/2. 
    H = H9/4.

    ! reads the input config file with: startWV, endWV, file name with atmospheric profile and line shape function name
    call readInputParameters
    
    ! initializes line shape function from the input config
    call fetchLineShapeFunction
    
    ! reads atmospheric profile arrays: height, pressure, temperature and density
    call readAtmosphericParameters
    
    ! reads and initializes the TIPS array
    call readTIPS

    reducedMoleculeName = inputMolecule
    
    ! open(atmControlUnit, file='control/PT-Protocol')

    do levelsIdx = 1, levels
        write(*,*) levelsIdx, levels ! for real time tracking how many levels has been processed
        pressure = pressureArray(levelsIdx)
        temperature = temperatureArray(levelsIdx)
        density = densityArray(levelsIdx)
        ! write(atmControlUnit, *) levelsIdx, pressure, temperature, levels

        unitlessT = refTemperature/temperature
        pSelf = density * 10. / LOSCHMIDT * temperature/stTemperature
        pForeign = pressure - pSelf

        levelLabel = '___'
        if ( levelsIdx < 10 ) then
            write(levelLabel(1:1), '(I1)') levelsIdx
        else
            if ( levelsIdx < 100 ) then
                write(levelLabel(1:2), '(I2)') levelsIdx
            else
                write(levelLabel(1:3), '(I2)') levelsIdx
            end if
        end if
        
        open(outputUnit, access='DIRECT', form='UNFORMATTED', recl=NT*4, &
            file='output/PT_CALC/'//levelLabel//'.'//reducedMoleculeName)
        ! RECL = NT for Windows Fortrans !

        startDeltaWV = startWV 
        endDeltaWV = startDeltaWV + deltaWV
        do while (startDeltaWV < endWV)
            ! *** calculation inside 10.0 cm^-1 *** !

            !! It considers that startWV, endWV and deltaWV should be multiples of 10
            outputRecNum = (startDeltaWV + 1.0) / 10.0 ! *** (0.0 -> 0 , 10.0 -> 1,..., 560.0 -> 56, etc.)
            ! write(*,*) startDeltaWV, V_END

            ! if ( extStartDeltaWV < startWV ) then
            !     extStartDeltaWV = startDeltaWV
            ! end if

            ! write(*,*) 'startDeltaWV before K_HITRAN call: ', startDeltaWV
            ! pause
            call processSpectra(inputMolecule, levelsIdx)

            write(outputUnit, rec=outputRecNum) RK

            startDeltaWV = startDeltaWV + deltaWV
            endDeltaWV = startDeltaWV + deltaWV
            
            ! *** end of the calculation inside 10.0 cm^-1 *** !
        end do
        close(outputUnit)
    end do
    ! close(atmControlUnit)
    write(*,*) ' *** Congratulations! PT-table is READY! ***'
    deallocate(heightArray)
    deallocate(pressureArray)
    deallocate(densityArray)
    deallocate(temperatureArray)
    deallocate(TIPS)
contains

    real function absorptionCoeffCalc(nu, temperatureParameter, lineShape)
        real, intent(in) :: temperatureParameter ! [K] -- temperature at the current atmospheric level
        real(kind=DP), intent(in) :: nu ! [cm-1],  gridWV -- spectral point where absorption coefficitent will be calculated
        procedure(shape), pointer, intent(in) :: lineShape ! [cm] -- normalized line shape function from the MyShapes module
        ! --------------------------------------------------- !
        real(kind=DP) :: X
        real(kind=DP) :: shiftedLineWV
        real :: intensity ! [cm-1/(molecule*cm-2)] (refLineIntensity) -- the spectral line intensity for a single molecule per unit volume.
        real :: TIPSFactor, boltzmannFactor, emissionFactor
        real :: TIPSOfT
        real :: TIPSOfRefT
        integer :: NTAB_G
        real :: C_G1, C_G2
        real :: t_G1
        integer :: isotopeNum

        shiftedLineWV = shiftedLinePosition(lineWV, pressure)
        X = abs(nu - shiftedLineWV)

        isotopeNum = jointMolIso / 100
        NTAB_G = (temperatureParameter - 20.0) / 2 + 1
        t_G1 = NTAB_G * 2.0 + 18.
        C_G2 = (temperatureParameter - t_G1)/2.
        C_G1 = 1. - C_G2
        TIPSOfT = C_G1 * TIPS(isotopeNum, NTAB_G) + C_G2 * TIPS(isotopeNum, NTAB_G+1)
        TIPSOfRefT = TIPS(isotopeNum, 139)

        TIPSFactor = TIPSOfRefT / TIPSOfT
        boltzmannFactor = exp(-C2*lineLowerState/temperatureParameter) / exp(-C2*lineLowerState/refTemperature)
        emissionFactor = (1 - exp(-C2*lineWV/temperatureParameter)) / (1 - exp(-C2*lineWV/refTemperature))

        intensity = refLineIntensity * TIPSFactor * boltzmannFactor * emissionFactor
        absorptionCoeffCalc = intensity * density * lineShape(X)
    end function absorptionCoeffCalc

    subroutine processSpectra(molecule, loopLevel)
        implicit none
        character(len=5), intent(in) :: molecule
        integer, intent(in) :: loopLevel
        
        integer, parameter :: hitranFileUnit = 7777 ! Unit of file with HITRAN data

        ! this save is to decouple the logic run only for the first call
        logical, save :: isFirstCall = .true.
        
        ! this save is for the keeping the current level. 
        ! It is calculated on the first call and then updates if the level changes in the calling procedure
        integer, save :: currentLevel ! JOLD
        
        ! this save is for the loop over height levels
        ! after the step into the new level, LBL starts from startingLineIdx
        integer, save :: startingLineIdx ! LINBEG0
        
        ! this save is for the loop over deltas (deltaWV)
        ! after the step into the next delta interval , we need to keep the lineIdx from the LBL calc
        integer, save :: lineIdx ! LINBEG 

        real(kind=DP), save :: startingLineWV ! VAA0

        ! this save is for
        real(kind=DP), save :: capWV
        
        ! real(kind=DP) :: VFISH ! *** ! extEndDeltaWV
        ! real(kind=DP) :: VA ! *** ! extStartDeltaWV
        ! real(kind=DP) :: VS ! the same as startDeltaWV
        ! real(kind=DP) :: VR4 ! the same as startDeltaWV

        integer :: iterRecNum
        real(kind=DP) :: iterLineWV

        integer :: I, J, M ! loop variables mainly for grid calculations
        
        ! TODO: moving `ifFirstCall` part to the separate subroutine, because
        ! it is only for reading from the HITRAN file and must be done only at once.

        ! TODO: deal with `totalLines` (now it is from HITEMP, but it seems that any large number is sufficient)

        ! TODO: deal with `molType`
        
        ! write(*,*) 'loopLevel: ', loopLevel
        ! write(*,*) 'startDeltaWV: ', startDeltaWV
        ! pause

        ! The first call operations:
        ! 1. Fetch the molecule name and its molType
        ! 2. Fetch corresponding HITRAN file and a total number of lines in this file
        ! 3. Interrupt if unsuported molecule
        ! 4. Establish starting position of the line in HITRAN file and the value of transition for this line -- for global interval from conifig: [startWV, endWV] interval
        !    cutOff -- included.

        if (isFirstCall) then
            isFirstCall = .false.
            startingLineIdx = 1
            currentLevel = 0
            lineIdx = 0
            select case (molecule)
            case ('H2O')
                molType = 1
                hitranFile = 'data/HITRAN16/H16.01'
                totalLines = 3892633
            case ('CO2')
                molType = 2
                hitranFile = 'data/HITRAN16/H16.02'
                totalLines = 10868410
            case ('SO2')
                molType = 1
                hitranFile = 'data/HITRAN16/H16.09'
                totalLines = 95120
            case default
                write(*,*) 'Molecule = ', molecule
                write(*,*) 'Unsupported type of the molecule !'
                ! stopping the calculation because of the unknown type of the molecule
                stop
            end select

            open(hitranFileUnit, access='DIRECT', form='UNFORMATTED', recl=36, file=hitranFile)
            ! Uncomment if the direct access file was created under Windows
            ! open(7777, access='DIRECT', form='UNFORMATTED', recl=9, file=hitranFile)

            read(hitranFileUnit, rec=startingLineIdx) startingLineWV
            if (startWV > cutOff) then
                extStartWV = startWV - cutOff
                iterRecNum = startingLineIdx
                iterLineWV = startingLineWV
                do while(iterLineWV <= extStartWV)
                    iterRecNum = iterRecNum + 1
                    read(hitranFileUnit, rec=iterRecNum) iterLineWV
                end do
                startingLineIdx = iterRecNum
                startingLineWV = iterLineWV
            end if
        end if

        ! TODO: move to the main.f90 file in the inner loop
        extStartDeltaWV = startDeltaWV - cutOff
        extEndDeltaWV = startDeltaWV + deltaWV + cutOff

        if ( currentLevel /= loopLevel ) then
            ! write(*,*) 'Level change !'
            ! write(*,*) 'current Level: ', currentLevel
            ! write(*,*) 'loop Level: ', loopLevel
            ! pause
            currentLevel = loopLevel
            lineIdx = startingLineIdx
        end if

        capWV = extStartDeltaWV + deltaWV
        if (capWV <= startingLineWV) capWV = startingLineWV

        ! VS = startDeltaWV
        !*-------------------------------------------------------------

        RK = 0.0
        RK0 = 0.0; RK0L = 0.0; RK0P = 0.0
        RK1 = 0.0; RK1L = 0.0; RK1P = 0.0
        RK2 = 0.0; RK2L = 0.0; RK2P = 0.0
        RK3 = 0.0; RK3L = 0.0; RK3P = 0.0
        RK4 = 0.0; RK4L = 0.0; RK4P = 0.0
        RK5 = 0.0; RK5L = 0.0; RK5P = 0.0
        RK6 = 0.0; RK6L = 0.0; RK6P = 0.0
        RK7 = 0.0; RK7L = 0.0; RK7P = 0.0
        RK8 = 0.0; RK8L = 0.0; RK8P = 0.0
        RK9 = 0.0; RK9L = 0.0; RK9P = 0.0

        !! Note: Arrays are initialized to zero at the beginning of each subroutine call.
        ! This approach ensures that the arrays have a clean state for each calculation.
        ! If the subroutine is called multiple times and the arrays do not need to be
        ! reset every time, consider optimizing by removing this initialization or
        ! modifying it as per the specific requirements of the program.

        !*--------------------------------------------------------------
        
        ! write(*,*) 'lineIdx before LBL2023: ', lineIdx
        ! pause
        call modernLBL(lineIdx, capWV, totalLines, currentLevel)
        ! write(*,*) 'lineIdx after LBL2023: ', lineIdx
        ! pause
        ! ------------ END OF THE FIRST PART ---------------------------------- !
        
        ! ----------------------SECOND PART ----------------------------------- !
        ! TODO: CREATE SUBROUTINE TO REMOVE REPETITIONS !
        ! be careful that last loop differs from NT0-NT8!
        
        do J = 1, NT0
            I = J * 2 - 1
            RK1P(I) = RK1P(I) + RK0P(J)
            RK1(I) = RK1(I) + RK0P(J) * 0.375 + RK0(J) * 0.75 - RK0L(J) * 0.125
            RK1L(I) = RK1L(I) + RK0(J)
            M = I + 1
            RK1P(M) = RK1P(M) + RK0(J)
            RK1(M) = RK1(M) + RK0L(J) * 0.375 + RK0(J) * 0.75 - RK0P(J) * 0.125
            RK1L(M) = RK1L(M) + RK0L(J)
        end do

        do J = 1, NT1
            I = J * 2 - 1
            RK2P(I) = RK2P(I) + RK1P(J)
            RK2(I) = RK2(I) + RK1P(J) * 0.375 + RK1(J) * 0.75 - RK1L(J) * 0.125
            RK2L(I) = RK2L(I) + RK1(J)
            M = I + 1
            RK2P(M) = RK2P(M) + RK1(J)
            RK2(M) = RK2(M) + RK1L(J) * 0.375 + RK1(J) * 0.75 - RK1P(J) * 0.125
            RK2L(M) = RK2L(M) + RK1L(J)
        end do

        do J = 1, NT2
            I = J * 2 - 1
            RK3P(I) = RK3P(I) + RK2P(J)
            RK3(I) = RK3(I) + RK2P(J) * 0.375 + RK2(J) * 0.75 - RK2L(J) * 0.125
            RK3L(I) = RK3L(I) + RK2(J)
            M = I + 1
            RK3P(M) = RK3P(M) + RK2(J)
            RK3(M) = RK3(M) + RK2L(J) * 0.375 + RK2(J) * 0.75 - RK2P(J) * 0.125
            RK3L(M) = RK3L(M) + RK2L(J)
        end do

        do J = 1, NT3
            I = J * 2 - 1
            RK4P(I) = RK4P(I) + RK3P(J)
            RK4(I) = RK4(I) + RK3P(J) * 0.375 + RK3(J) * 0.75 - RK3L(J) * 0.125
            RK4L(I) = RK4L(I) + RK3(J)
            M = I + 1
            RK4P(M) = RK4P(M) + RK3(J)
            RK4(M) = RK4(M) + RK3L(J) * 0.375 + RK3(J) * 0.75 - RK3P(J) * 0.125
            RK4L(M) = RK4L(M) + RK3L(J)
        end do

        do J = 1, NT4
            I = J * 2 - 1
            RK5P(I) = RK5P(I) + RK4P(J)
            RK5(I) = RK5(I) + RK4P(J) * 0.375 + RK4(J) * 0.75 - RK4L(J) * 0.125
            RK5L(I) = RK5L(I) + RK4(J)
            M = I + 1
            RK5P(M) = RK5P(M) + RK4(J)
            RK5(M) = RK5(M) + RK4L(J) * 0.375 + RK4(J) * 0.75 - RK4P(J) * 0.125
            RK5L(M) = RK5L(M) + RK4L(J)
        end do

        do J = 1, NT5
            I = J * 2 - 1
            RK6P(I) = RK6P(I) + RK5P(J)
            RK6(I) = RK6(I) + RK5P(J) * 0.375 + RK5(J) * 0.75 - RK5L(J) * 0.125
            RK6L(I) = RK6L(I) + RK5(J)
            M = I + 1
            RK6P(M) = RK6P(M) + RK5(J)
            RK6(M) = RK6(M) + RK5L(J) * 0.375 + RK5(J) * 0.75 - RK5P(J) * 0.125
            RK6L(M) = RK6L(M) + RK5L(J)
        end do
        
        do J = 1, NT6
            I = J * 2 - 1
            RK7P(I) = RK7P(I) + RK6P(J)
            RK7(I) = RK7(I) + RK6P(J) * 0.375 + RK6(J) * 0.75 - RK6L(J) * 0.125
            RK7L(I) = RK7L(I) + RK6(J)
            M = I + 1
            RK7P(M) = RK7P(M) + RK6(J)
            RK7(M) = RK7(M) + RK6L(J) * 0.375 + RK6(J) * 0.75 - RK6P(J) * 0.125
            RK7L(M) = RK7L(M) + RK6L(J)
        end do

        do J = 1, NT7
            I = J * 2 - 1
            RK8P(I) = RK8P(I) + RK7P(J)
            RK8(I) = RK8(I) + RK7P(J) * 0.375 + RK7(J) * 0.75 - RK7L(J) * 0.125
            RK8L(I) = RK8L(I) + RK7(J)
            M = I + 1
            RK8P(M) = RK8P(M) + RK7(J)
            RK8(M) = RK8(M) + RK7L(J) * 0.375 + RK7(J) * 0.75 - RK7P(J) * 0.125
            RK8L(M) = RK8L(M) + RK7L(J)
        end do

        do J = 1, NT8
            I = J * 2 - 1
            RK9P(I) = RK9P(I) + RK8P(J)
            RK9(I) = RK9(I) + RK8P(J) * 0.375 + RK8(J) * 0.75 - RK8L(J) * 0.125
            RK9L(I)= RK9L(I) + RK8(J)
            M = I + 1
            RK9P(M) = RK9P(M) + RK8(J)
            RK9(M) = RK9(M) + RK8L(J) * 0.375 + RK8(J) * 0.75 - RK8P(J) * 0.125
            RK9L(M)= RK9L(M) + RK8L(J)
        end do

        I=1
        do J = 1, NT9
            I = I+1
            RK(I) = RK(I) + (RK9P(J) * 0.375 + RK9(J) * 0.75 - RK9L(J) * 0.125)
            I = I+1
            RK(I) = RK(I) + RK9(J)
            I = I+1
            RK(I) = RK(I) + (RK9L(J) * 0.375 + RK9(J) * 0.75 - RK9P(J) * 0.125)
            I = I + 1
            RK(I) = RK(I) + RK9L(J)
        end do
    end subroutine processSpectra
end program main
